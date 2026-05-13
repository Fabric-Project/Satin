// BokehDepthOfFieldPostProcessor
//
// Reference lineage:
// - "Circular Dof" by Kleber Garcia ("Kecho"), popularized in simplified form on Shadertoy:
//   https://shadertoy.com/view/Xd2BWc
// - "Circular Depth of Field" / Frostbite-style circular DOF presentations by Kleber Garcia, GDC 2018:
//   https://media.gdcvault.com/gdc2018/presentations/Garcia_Kleber_CircularDepthOf.pdf
// - The related ACM talk/paper cited from the original shader comments:
//   http://dl.acm.org/citation.cfm?id=3085022
//
// Satin's implementation is inspired by that family of circular/bokeh DOF pipelines, but it is not a
// line-for-line port. In particular, the prefilter step classifies near/far blur directly from reconstructed
// view distance and the subsequent passes operate on split near/far buffers plus a near-radius dilation pass.
//
// Current investigation notes:
// - Scenes with cleared depth behind geometry can show silhouette-shaped CoC plateaus around defocused objects.
// - This is most visible where background depth resolves to the clear value and where thin geometry overlaps
//   strongly blurred regions.
// - If DOF artifacts are being debugged, start in the prefilter shader where cleared depth is promoted to
//   max far blur and where near/far coverage is accumulated before the complex blur stages.
//
import Metal
import simd

open class BokehDepthOfFieldPostProcessor: PostProcessor {
    private static let defaultResolutionScale: Float = 0.5
    private static let minResolutionScale: Float = 0.25
    private static let maxResolutionScale: Float = 1.0
    private static let defaultFocusDistance: Float = 4.0
    private static let defaultFocusRange: Float = 1.5
    private static let defaultMaxBlurRadius: Float = 6.0

    private final class NamedComputeProcessor: TextureComputeProcessor {
        private let shaderLabel: String
        private let updateFunctionName: String

        init(device: MTLDevice, pipelineURL: URL, label: String, updateFunctionName: String) {
            shaderLabel = label
            self.updateFunctionName = updateFunctionName
            super.init(device: device, pipelineURL: pipelineURL)
            self.label = label
        }

        override func createShader() -> ComputeShader {
            let shader = ComputeShader(
                label: shaderLabel,
                resetFunctionName: "",
                updateFunctionName: updateFunctionName,
                pipelineURL: pipelineURL,
                live: live
            )
            shader.delegate = self
            return shader
        }
    }

    public var colorTexture: MTLTexture? {
        didSet { compositeMaterial.colorTexture = colorTexture }
    }

    public var depthTexture: MTLTexture? {
        didSet {
            compositeMaterial.depthTexture = depthTexture
        }
    }

    public var sceneCamera: Camera?

    public let parameters: ParameterGroup = ParameterGroup("Depth Of Field", [
        FloatParameter(
            "Focus Distance",
            defaultFocusDistance,
            0.001,
            10.0,
            .slider,
            "Distance from the camera that stays sharp."
        ),
        FloatParameter(
            "Focus Range",
            defaultFocusRange,
            0.001,
            10.0,
            .slider,
            "Full depth band that remains acceptably sharp."
        ),
        FloatParameter(
            "Max Blur Radius",
            defaultMaxBlurRadius,
            0.0,
            32.0,
            .slider,
            "Maximum circle-of-confusion radius in full-resolution pixels."
        ),
        FloatParameter(
            "Resolution Scale",
            defaultResolutionScale,
            minResolutionScale,
            maxResolutionScale,
            .slider,
            "Internal processing resolution relative to the main color buffer."
        ),
    ])

    public var focusDistance: Float {
        get { parameters.get("Focus Distance", as: FloatParameter.self)?.value ?? Self.defaultFocusDistance }
        set { parameters.get("Focus Distance", as: FloatParameter.self)?.value = newValue }
    }

    public var focusRange: Float {
        get { parameters.get("Focus Range", as: FloatParameter.self)?.value ?? Self.defaultFocusRange }
        set { parameters.get("Focus Range", as: FloatParameter.self)?.value = newValue }
    }

    public var maxBlurRadius: Float {
        get { parameters.get("Max Blur Radius", as: FloatParameter.self)?.value ?? Self.defaultMaxBlurRadius }
        set { parameters.get("Max Blur Radius", as: FloatParameter.self)?.value = newValue }
    }

    public var resolutionScale: Float {
        get { parameters.get("Resolution Scale", as: FloatParameter.self)?.value ?? Self.defaultResolutionScale }
        set { parameters.get("Resolution Scale", as: FloatParameter.self)?.value = Self.clampResolutionScale(newValue) }
    }

    public private(set) var outputTexture: MTLTexture?

    private let compositeMaterial: BokehDepthOfFieldCompositeMaterial
    private let prefilterProcessor: NamedComputeProcessor
    private let splitProcessor: NamedComputeProcessor
    private let nearMaxHorizontalProcessor: NamedComputeProcessor
    private let nearMaxVerticalProcessor: NamedComputeProcessor
    private let complexHorizontalProcessor: NamedComputeProcessor
    private let complexVerticalProcessor: NamedComputeProcessor

    private var sourceColorTexture: MTLTexture?
    private var cocTexture: MTLTexture?
    private var nearColorTexture: MTLTexture?
    private var farColorTexture: MTLTexture?
    private var nearRadiusTexture: MTLTexture?
    private var nearRadiusMaxIntermediateTexture: MTLTexture?
    private var nearRadiusMaxTexture: MTLTexture?
    private var farRadiusTexture: MTLTexture?
    private var nearBlurTexture: MTLTexture?
    private var farBlurTexture: MTLTexture?
    private var nearComplexTextures: [MTLTexture] = []
    private var farComplexTextures: [MTLTexture] = []

    private var lastSize: (width: Float, height: Float) = (0, 0)
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)
    private var processingTextureSize: (width: Int, height: Int) = (0, 0)
    private var appliedResolutionScale = BokehDepthOfFieldPostProcessor.defaultResolutionScale

    private static func clampResolutionScale(_ value: Float) -> Float {
        min(max(value, Self.minResolutionScale), Self.maxResolutionScale)
    }

    public required init(context: Context) {
        let compositeContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
        compositeMaterial = BokehDepthOfFieldCompositeMaterial(context: compositeContext)

        let pipelineURL = getPipelinesComputeURL("BokehDepthOfField")!.appendingPathComponent("Shaders.metal")
        prefilterProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Prefilter",
            updateFunctionName: "bokehDepthOfFieldPrefilterUpdate"
        )
        splitProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Split",
            updateFunctionName: "bokehDepthOfFieldSplitUpdate"
        )
        nearMaxHorizontalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near Max Horizontal",
            updateFunctionName: "bokehDepthOfFieldNearMaxHorizontalUpdate"
        )
        nearMaxVerticalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near Max Vertical",
            updateFunctionName: "bokehDepthOfFieldNearMaxVerticalUpdate"
        )
        complexHorizontalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Complex Horizontal",
            updateFunctionName: "bokehDepthOfFieldComplexHorizontalUpdate"
        )
        complexVerticalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Complex Vertical",
            updateFunctionName: "bokehDepthOfFieldComplexVerticalUpdate"
        )

        super.init(
            label: "Bokeh Depth Of Field",
            context: compositeContext,
            material: compositeMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
    }

    override open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        let force: Bool = lastSize != size

        if force {
            super.resize(size: size, scaleFactor: scaleFactor)
            resizeResourcesIfNeeded(force: force)
        }

        lastSize = size
    }

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        resizeResourcesIfNeeded(force: false)

        guard let colorTexture,
              let depthTexture,
              let sceneCamera,
              let outputTexture,
              let sourceColorTexture,
              let cocTexture,
              let nearColorTexture,
              let farColorTexture,
              let nearRadiusTexture,
              let nearRadiusMaxIntermediateTexture,
              let nearRadiusMaxTexture,
              let farRadiusTexture,
              let nearBlurTexture,
              let farBlurTexture,
              nearComplexTextures.count == 4,
              farComplexTextures.count == 4
        else { return }

        let scaledBlurRadius = max(maxBlurRadius * appliedResolutionScale, 0.0)

        prefilterProcessor.set("Inverse Projection Matrix", sceneCamera.projectionMatrix.inverse)
        prefilterProcessor.set("Focus Distance", focusDistance)
        prefilterProcessor.set("Focus Range", focusRange)
        prefilterProcessor.set("Max Blur Radius", scaledBlurRadius)
        prefilterProcessor.set(sourceColorTexture, index: .Custom0)
        prefilterProcessor.set(cocTexture, index: .Custom1)
        prefilterProcessor.set(colorTexture, index: .Custom4)
        prefilterProcessor.set(depthTexture, index: .Custom5)
        prefilterProcessor.update(commandBuffer)

        splitProcessor.set("Max Blur Radius", scaledBlurRadius)
        splitProcessor.set(nearColorTexture, index: .Custom0)
        splitProcessor.set(farColorTexture, index: .Custom1)
        splitProcessor.set(nearRadiusTexture, index: .Custom2)
        splitProcessor.set(farRadiusTexture, index: .Custom3)
        splitProcessor.set(sourceColorTexture, index: .Custom4)
        splitProcessor.set(cocTexture, index: .Custom5)
        splitProcessor.update(commandBuffer)

        let nearMaxRadius = Int(min(max(Int(ceil(scaledBlurRadius)), 0), 24))
        nearMaxHorizontalProcessor.set("Max Radius", nearMaxRadius)
        nearMaxHorizontalProcessor.set(nearRadiusMaxIntermediateTexture, index: .Custom0)
        nearMaxHorizontalProcessor.set(nearRadiusTexture, index: .Custom1)
        nearMaxHorizontalProcessor.update(commandBuffer)

        nearMaxVerticalProcessor.set("Max Radius", nearMaxRadius)
        nearMaxVerticalProcessor.set(nearRadiusMaxTexture, index: .Custom0)
        nearMaxVerticalProcessor.set(nearRadiusMaxIntermediateTexture, index: .Custom1)
        nearMaxVerticalProcessor.update(commandBuffer)

        bindHorizontalPass(
            sourceTexture: nearColorTexture,
            radiusTexture: nearRadiusMaxTexture,
            outputTextures: nearComplexTextures
        )
        complexHorizontalProcessor.update(commandBuffer)

        bindHorizontalPass(
            sourceTexture: farColorTexture,
            radiusTexture: farRadiusTexture,
            outputTextures: farComplexTextures
        )
        complexHorizontalProcessor.update(commandBuffer)

        bindVerticalPass(
            radiusTexture: nearRadiusMaxTexture,
            outputTexture: nearBlurTexture,
            complexTextures: nearComplexTextures
        )
        complexVerticalProcessor.update(commandBuffer)

        bindVerticalPass(
            radiusTexture: farRadiusTexture,
            outputTexture: farBlurTexture,
            complexTextures: farComplexTextures
        )
        complexVerticalProcessor.update(commandBuffer)

        compositeMaterial.colorTexture = colorTexture
        compositeMaterial.depthTexture = depthTexture
        compositeMaterial.farBlurTexture = farBlurTexture
        compositeMaterial.nearBlurTexture = nearBlurTexture
        compositeMaterial.update(camera: sceneCamera)
        compositeMaterial.focusDistance = focusDistance
        compositeMaterial.focusRange = focusRange
        compositeMaterial.maxBlurRadius = scaledBlurRadius

        super.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    private func bindHorizontalPass(sourceTexture: MTLTexture, radiusTexture: MTLTexture, outputTextures: [MTLTexture]) {
        complexHorizontalProcessor.set(outputTextures[0], index: .Custom0)
        complexHorizontalProcessor.set(outputTextures[1], index: .Custom1)
        complexHorizontalProcessor.set(outputTextures[2], index: .Custom2)
        complexHorizontalProcessor.set(outputTextures[3], index: .Custom3)
        complexHorizontalProcessor.set(sourceTexture, index: .Custom4)
        complexHorizontalProcessor.set(radiusTexture, index: .Custom5)
    }

    private func bindVerticalPass(radiusTexture: MTLTexture, outputTexture: MTLTexture, complexTextures: [MTLTexture]) {
        complexVerticalProcessor.set(outputTexture, index: .Custom0)
        complexVerticalProcessor.set(complexTextures[0], index: .Custom1)
        complexVerticalProcessor.set(complexTextures[1], index: .Custom2)
        complexVerticalProcessor.set(complexTextures[2], index: .Custom3)
        complexVerticalProcessor.set(complexTextures[3], index: .Custom4)
        complexVerticalProcessor.set(radiusTexture, index: .Custom5)
    }

    private func resizeResourcesIfNeeded(force: Bool) {
        let clampedResolutionScale = Self.clampResolutionScale(resolutionScale)
        if clampedResolutionScale != resolutionScale {
            resolutionScale = clampedResolutionScale
        }

        let outputWidth = Int(max(lastSize.width.rounded(.up), 0.0))
        let outputHeight = Int(max(lastSize.height.rounded(.up), 0.0))
        let processingWidth = Int(max((lastSize.width * clampedResolutionScale).rounded(.up), 0.0))
        let processingHeight = Int(max((lastSize.height * clampedResolutionScale).rounded(.up), 0.0))

        if outputWidth <= 0 || outputHeight <= 0 || processingWidth <= 0 || processingHeight <= 0 {
            outputTexture = nil
            sourceColorTexture = nil
            cocTexture = nil
            nearColorTexture = nil
            farColorTexture = nil
            nearRadiusTexture = nil
            nearRadiusMaxIntermediateTexture = nil
            nearRadiusMaxTexture = nil
            farRadiusTexture = nil
            nearBlurTexture = nil
            farBlurTexture = nil
            nearComplexTextures = []
            farComplexTextures = []
            outputTextureSize = (0, 0)
            processingTextureSize = (0, 0)
            return
        }

        if force || outputTextureSize.width != outputWidth || outputTextureSize.height != outputHeight {
            outputTexture = makeTexture(
                device: context.device,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: context.colorPixelFormat,
                usage: [.renderTarget, .shaderRead],
                storageMode: .private,
                label: "Bokeh DOF Output"
            )
            outputTextureSize = (outputWidth, outputHeight)
        }

        if force ||
            processingTextureSize.width != processingWidth ||
            processingTextureSize.height != processingHeight ||
            appliedResolutionScale != clampedResolutionScale
        {
            sourceColorTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Source Color"
            )
            cocTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rg16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF CoC"
            )
            nearColorTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near Color"
            )
            farColorTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Far Color"
            )
            nearRadiusTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite, .renderTarget],
                storageMode: .private,
                label: "Bokeh DOF Near Radius"
            )
            nearRadiusMaxIntermediateTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near Radius Max Intermediate"
            )
            nearRadiusMaxTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near Radius Max"
            )
            farRadiusTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Far Radius"
            )
            nearBlurTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near Blur"
            )
            farBlurTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Far Blur"
            )
            nearComplexTextures = makeComplexTextures(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                labelPrefix: "Bokeh DOF Near Complex"
            )
            farComplexTextures = makeComplexTextures(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                labelPrefix: "Bokeh DOF Far Complex"
            )
            processingTextureSize = (processingWidth, processingHeight)
            appliedResolutionScale = clampedResolutionScale
        }
    }

    private func makeComplexTextures(device: MTLDevice, width: Int, height: Int, labelPrefix: String) -> [MTLTexture] {
        (0 ..< 4).compactMap { index in
            makeTexture(
                device: device,
                width: width,
                height: height,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "\(labelPrefix) \(index)"
            )
        }
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage,
        storageMode: MTLStorageMode,
        label: String
    ) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
