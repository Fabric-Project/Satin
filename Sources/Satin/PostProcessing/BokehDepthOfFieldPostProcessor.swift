// BokehDepthOfFieldPostProcessor
//
// Reference lineage and porting goals:
// - Kleber Garcia, "Circular Depth of Field", GDC 2018:
//   https://media.gdcvault.com/gdc2018/presentations/Garcia_Kleber_CircularDepthOf.pdf
// - The associated ACM talk/paper cited from the original shader comments:
//   http://dl.acm.org/citation.cfm?id=3085022
// - Erfan Ahmadi's "Bokeh Depth Of Field" reference implementation, specifically the
//   separable circular DOF path in src/29_DepthOfField/Shaders/Metal:
//   https://github.com/Erfan-Ahmadi/BokehDepthOfField
//
// Satin keeps its public "focus distance / focus range / max blur radius / resolution scale"
// surface, but internally ports the reference pipeline structure as faithfully as possible:
// 1. full-resolution near/far CoC generation
// 2. half-resolution downsample producing CoC, center color, and far-premultiplied color
// 3. near CoC box filter
// 4. near CoC max filter
// 5. separable horizontal circular DOF accumulation
// 6. final fullscreen composite that performs the vertical pass and blends explicit near/far planes
//
// Accuracy of the pass graph and blend law takes priority over optimization in this implementation.
import Metal
import simd

open class BokehDepthOfFieldPostProcessor: PostProcessor {
    private static let defaultResolutionScale: Float = 0.5
    private static let minResolutionScale: Float = 0.25
    private static let maxResolutionScale: Float = 1.0
    private static let defaultFocusDistance: Float = 4.0
    private static let defaultFocusRange: Float = 1.5
    private static let defaultMaxBlurRadius: Float = 6.0
    private static let defaultBlend: Float = 1.0
    private static let referenceNearCoCFilterRadius = 6

    public struct ExplicitCoCBands: Equatable {
        public let nearBegin: Float
        public let nearEnd: Float
        public let farBegin: Float
        public let farEnd: Float

        public init(nearBegin: Float, nearEnd: Float, farBegin: Float, farEnd: Float) {
            self.nearBegin = nearBegin
            self.nearEnd = nearEnd
            self.farBegin = farBegin
            self.farEnd = farEnd
        }
    }

    struct ResolvedDOFSettings: Equatable {
        let maxRadius: Float
        let blend: Float
        let nearBegin: Float
        let nearEnd: Float
        let farBegin: Float
        let farEnd: Float
    }

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

    public var depthTexture: MTLTexture?
    public var sceneCamera: Camera?

    public let parameters: ParameterGroup = ParameterGroup("Depth Of Field", [
        FloatParameter(
            "Focus Distance",
            defaultFocusDistance,
            0.001,
            1000.0,
            .slider,
            "Distance from the camera that stays sharp."
        ),
        FloatParameter(
            "Focus Range",
            defaultFocusRange,
            0.001,
            1000.0,
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
        FloatParameter(
            "Blend",
            defaultBlend,
            0.0,
            4.0,
            .slider,
            "Reference blend multiplier applied during near and far compositing."
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

    public var blend: Float {
        get { parameters.get("Blend", as: FloatParameter.self)?.value ?? Self.defaultBlend }
        set { parameters.get("Blend", as: FloatParameter.self)?.value = newValue }
    }

    public var explicitCoCBands: ExplicitCoCBands?

    public private(set) var outputTexture: MTLTexture?

    private let compositeMaterial: BokehDepthOfFieldCompositeMaterial
    private let generateCoCProcessor: NamedComputeProcessor
    private let downsampleProcessor: NamedComputeProcessor
    private let nearCoCBoxHorizontalProcessor: NamedComputeProcessor
    private let nearCoCBoxVerticalProcessor: NamedComputeProcessor
    private let nearCoCMaxHorizontalProcessor: NamedComputeProcessor
    private let nearCoCMaxVerticalProcessor: NamedComputeProcessor
    private let horizontalProcessor: NamedComputeProcessor

    private(set) var fullResolutionCoCTexture: MTLTexture?
    private(set) var downsampledCoCTexture: MTLTexture?
    private(set) var sourceColorTexture: MTLTexture?
    private(set) var colorMulFarTexture: MTLTexture?
    private(set) var nearCoCBoxIntermediateTexture: MTLTexture?
    private(set) var nearCoCBoxTexture: MTLTexture?
    private(set) var nearCoCMaxIntermediateTexture: MTLTexture?
    private(set) var nearCoCTexture: MTLTexture?
    private(set) var farHorizontalTextures: [MTLTexture] = []
    private(set) var nearHorizontalTextures: [MTLTexture] = []
    private(set) var farWeightsTexture: MTLTexture?

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
        generateCoCProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Generate CoC",
            updateFunctionName: "bokehDepthOfFieldGenerateCoCUpdate"
        )
        downsampleProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Downsample",
            updateFunctionName: "bokehDepthOfFieldDownsampleUpdate"
        )
        nearCoCBoxHorizontalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near CoC Box Horizontal",
            updateFunctionName: "bokehDepthOfFieldNearCoCBoxHorizontalUpdate"
        )
        nearCoCBoxVerticalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near CoC Box Vertical",
            updateFunctionName: "bokehDepthOfFieldNearCoCBoxVerticalUpdate"
        )
        nearCoCMaxHorizontalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near CoC Max Horizontal",
            updateFunctionName: "bokehDepthOfFieldNearCoCMaxHorizontalUpdate"
        )
        nearCoCMaxVerticalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Near CoC Max Vertical",
            updateFunctionName: "bokehDepthOfFieldNearCoCMaxVerticalUpdate"
        )
        horizontalProcessor = NamedComputeProcessor(
            device: context.device,
            pipelineURL: pipelineURL,
            label: "Bokeh DOF Horizontal",
            updateFunctionName: "bokehDepthOfFieldHorizontalUpdate"
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
        let force = lastSize != size
        lastSize = size

        if force {
            super.resize(size: size, scaleFactor: scaleFactor)
            resizeResourcesIfNeeded(force: force)
        }
    }

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        resizeResourcesIfNeeded(force: false)

        guard let colorTexture,
              let depthTexture,
              let sceneCamera,
              let outputTexture,
              let fullResolutionCoCTexture,
              let downsampledCoCTexture,
              let sourceColorTexture,
              let colorMulFarTexture,
              let nearCoCBoxIntermediateTexture,
              let nearCoCBoxTexture,
              let nearCoCMaxIntermediateTexture,
              let nearCoCTexture,
              let farWeightsTexture,
              farHorizontalTextures.count == 3,
              nearHorizontalTextures.count == 3
        else { return }

        let resolvedSettings = resolvedSettings()

        generateCoCProcessor.set("Near Plane", sceneCamera.near)
        generateCoCProcessor.set("Far Plane", sceneCamera.far)
        generateCoCProcessor.set("Near Begin", resolvedSettings.nearBegin)
        generateCoCProcessor.set("Near End", resolvedSettings.nearEnd)
        generateCoCProcessor.set("Far Begin", resolvedSettings.farBegin)
        generateCoCProcessor.set("Far End", resolvedSettings.farEnd)
        generateCoCProcessor.set(fullResolutionCoCTexture, index: .Custom0)
        generateCoCProcessor.set(depthTexture, index: .Custom1)
        generateCoCProcessor.update(commandBuffer)

        downsampleProcessor.set("Far Boost", Float(5.0))
        downsampleProcessor.set(downsampledCoCTexture, index: .Custom0)
        downsampleProcessor.set(sourceColorTexture, index: .Custom1)
        downsampleProcessor.set(colorMulFarTexture, index: .Custom2)
        downsampleProcessor.set(fullResolutionCoCTexture, index: .Custom3)
        downsampleProcessor.set(colorTexture, index: .Custom4)
        downsampleProcessor.update(commandBuffer)

        let nearFilterRadius = nearCoCFilterRadius(for: resolvedSettings)
        nearCoCBoxHorizontalProcessor.set(nearCoCBoxIntermediateTexture, index: .Custom0)
        nearCoCBoxHorizontalProcessor.set("Filter Radius", nearFilterRadius)
        nearCoCBoxHorizontalProcessor.set(downsampledCoCTexture, index: .Custom1)
        nearCoCBoxHorizontalProcessor.update(commandBuffer)

        nearCoCBoxVerticalProcessor.set(nearCoCBoxTexture, index: .Custom0)
        nearCoCBoxVerticalProcessor.set("Filter Radius", nearFilterRadius)
        nearCoCBoxVerticalProcessor.set(nearCoCBoxIntermediateTexture, index: .Custom1)
        nearCoCBoxVerticalProcessor.update(commandBuffer)

        nearCoCMaxHorizontalProcessor.set(nearCoCMaxIntermediateTexture, index: .Custom0)
        nearCoCMaxHorizontalProcessor.set("Filter Radius", nearFilterRadius)
        nearCoCMaxHorizontalProcessor.set(nearCoCBoxTexture, index: .Custom1)
        nearCoCMaxHorizontalProcessor.update(commandBuffer)

        nearCoCMaxVerticalProcessor.set(nearCoCTexture, index: .Custom0)
        nearCoCMaxVerticalProcessor.set("Filter Radius", nearFilterRadius)
        nearCoCMaxVerticalProcessor.set(nearCoCMaxIntermediateTexture, index: .Custom1)
        nearCoCMaxVerticalProcessor.update(commandBuffer)

        horizontalProcessor.set("Max Radius", resolvedSettings.maxRadius)
        horizontalProcessor.set(farHorizontalTextures[0], index: .Custom0)
        horizontalProcessor.set(farHorizontalTextures[1], index: .Custom1)
        horizontalProcessor.set(farHorizontalTextures[2], index: .Custom2)
        horizontalProcessor.set(nearHorizontalTextures[0], index: .Custom3)
        horizontalProcessor.set(nearHorizontalTextures[1], index: .Custom4)
        horizontalProcessor.set(nearHorizontalTextures[2], index: .Custom5)
        horizontalProcessor.set(farWeightsTexture, index: .Custom6)
        horizontalProcessor.set(sourceColorTexture, index: .Custom7)
        horizontalProcessor.set(downsampledCoCTexture, index: .Custom8)
        horizontalProcessor.set(nearCoCTexture, index: .Custom9)
        horizontalProcessor.set(colorMulFarTexture, index: .Custom10)
        horizontalProcessor.update(commandBuffer)

        compositeMaterial.colorTexture = colorTexture
        compositeMaterial.cocTexture = downsampledCoCTexture
        compositeMaterial.farRTexture = farHorizontalTextures[0]
        compositeMaterial.farGTexture = farHorizontalTextures[1]
        compositeMaterial.farBTexture = farHorizontalTextures[2]
        compositeMaterial.nearRTexture = nearHorizontalTextures[0]
        compositeMaterial.nearGTexture = nearHorizontalTextures[1]
        compositeMaterial.nearBTexture = nearHorizontalTextures[2]
        compositeMaterial.nearCoCTexture = nearCoCTexture
        compositeMaterial.farWeightsTexture = farWeightsTexture
        compositeMaterial.maxBlurRadius = resolvedSettings.maxRadius
        compositeMaterial.blend = resolvedSettings.blend

        super.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    func resolvedSettings() -> ResolvedDOFSettings {
        let scaledMaxRadius = max(maxBlurRadius * appliedResolutionScale, 0.0)
        let cocBands = explicitCoCBands ?? deriveCompatibilityCoCBands(
            focusDistance: focusDistance,
            focusRange: focusRange
        )
        return ResolvedDOFSettings(
            maxRadius: scaledMaxRadius,
            blend: blend,
            nearBegin: cocBands.nearBegin,
            nearEnd: cocBands.nearEnd,
            farBegin: cocBands.farBegin,
            farEnd: cocBands.farEnd
        )
    }

    private func nearCoCFilterRadius(for resolvedSettings: ResolvedDOFSettings) -> Int {
        max(Self.referenceNearCoCFilterRadius, Int(ceil(resolvedSettings.maxRadius)))
    }

    private func deriveCompatibilityCoCBands(focusDistance: Float, focusRange: Float) -> ExplicitCoCBands {
        let halfRange = max(focusRange * 0.5, 1.0e-4)
        let nearEnd = max(focusDistance - halfRange, 1.0e-4)
        let farBegin = focusDistance + halfRange
        let nearBegin = max(nearEnd - max(focusRange, 1.0e-4), 1.0e-4)
        let farEnd = farBegin + max(focusRange, 1.0e-4)
        return ExplicitCoCBands(
            nearBegin: nearBegin,
            nearEnd: nearEnd,
            farBegin: farBegin,
            farEnd: farEnd
        )
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
            fullResolutionCoCTexture = nil
            downsampledCoCTexture = nil
            sourceColorTexture = nil
            colorMulFarTexture = nil
            nearCoCBoxIntermediateTexture = nil
            nearCoCBoxTexture = nil
            nearCoCMaxIntermediateTexture = nil
            nearCoCTexture = nil
            farHorizontalTextures = []
            nearHorizontalTextures = []
            farWeightsTexture = nil
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
            fullResolutionCoCTexture = makeTexture(
                device: context.device,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: .rg16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Full CoC"
            )
            outputTextureSize = (outputWidth, outputHeight)
        }

        if force ||
            processingTextureSize.width != processingWidth ||
            processingTextureSize.height != processingHeight ||
            appliedResolutionScale != clampedResolutionScale
        {
            downsampledCoCTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rg16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF CoC"
            )
            sourceColorTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Source Color"
            )
            colorMulFarTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Color Mul Far"
            )
            nearCoCBoxIntermediateTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near CoC Box Intermediate"
            )
            nearCoCBoxTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near CoC Box"
            )
            nearCoCMaxIntermediateTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near CoC Max Intermediate"
            )
            nearCoCTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Near CoC"
            )
            farHorizontalTextures = makeComponentTextures(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                labels: ["Bokeh DOF Far R", "Bokeh DOF Far G", "Bokeh DOF Far B"]
            )
            nearHorizontalTextures = makeComponentTextures(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                labels: ["Bokeh DOF Near R", "Bokeh DOF Near G", "Bokeh DOF Near B"]
            )
            farWeightsTexture = makeTexture(
                device: context.device,
                width: processingWidth,
                height: processingHeight,
                pixelFormat: .r16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: "Bokeh DOF Far Weights"
            )
            processingTextureSize = (processingWidth, processingHeight)
            appliedResolutionScale = clampedResolutionScale
        }
    }

    private func makeComponentTextures(device: MTLDevice, width: Int, height: Int, labels: [String]) -> [MTLTexture] {
        labels.compactMap { label in
            makeTexture(
                device: device,
                width: width,
                height: height,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .shaderWrite],
                storageMode: .private,
                label: label
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
