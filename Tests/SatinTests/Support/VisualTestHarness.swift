import CoreGraphics
import Foundation
import ImageIO
import Metal
import Satin
import UniformTypeIdentifiers
import XCTest

struct RGBAImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

struct VisualDiffResult {
    let meanAbsoluteDifference: Double
    let maxAbsoluteDifference: UInt8
    let differingPixelCount: Int
    let totalPixelCount: Int
    let diffImage: RGBAImage
}

struct ContentCoverageResult {
    let changedPixelCount: Int
    let totalPixelCount: Int
    let changedPixelRatio: Double
    let meanNormalizedDifference: Double
}

struct ImageRegion {
    let name: String
    let normalizedRect: CGRect
}

enum ReferenceImageLocation {
    case bundle(name: String)
    case disk(URL)

    var url: URL? {
        switch self {
        case let .bundle(name):
            return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "VisualReferences")
                ?? Bundle.module.url(forResource: name, withExtension: "png")
        case let .disk(url):
            return url
        }
    }

    var filename: String {
        switch self {
        case let .bundle(name):
            return "\(name).png"
        case let .disk(url):
            return url.lastPathComponent
        }
    }
}

enum VisualTestHarness {
    static let recordModeEnvironmentKey = "SATIN_RECORD_REFERENCE_IMAGES"
    static let failureArtifactsDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SatinVisualDiffs", isDirectory: true)
    static let defaultClearColor = simd_float4(0.08, 0.08, 0.1, 1.0)
    static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/VisualReferences", isDirectory: true)

    static var isRecordingReferences: Bool {
        ProcessInfo.processInfo.environment[recordModeEnvironmentKey] == "1"
    }

    static func makeContext(device: MTLDevice) -> Context {
        Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float
        )
    }

    static func render(
        size: SIMD2<Int>,
        configure: (Renderer, Camera) -> (scene: Object, camera: Camera)
    ) throws -> RGBAImage {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "VisualTestHarness", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal is unavailable"])
        }

        guard let commandQueue = device.makeCommandQueue() else {
            throw NSError(domain: "VisualTestHarness", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }

        let context = makeContext(device: device)
        let renderer = Renderer(context: context, clearColor: defaultClearColor)
        renderer.resize((width: Float(size.x), height: Float(size.y)))

        let camera = PerspectiveCamera(position: [0, 0, 5], near: 0.1, far: 100.0, fov: 30.0)
        camera.aspect = Float(size.x) / Float(size.y)

        let sceneResult = configure(renderer, camera)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = readableTextureStorageMode

        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "VisualTestHarness", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw NSError(domain: "VisualTestHarness", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
        }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: sceneResult.scene,
            camera: sceneResult.camera,
            renderTarget: outputTexture
        )

        if readableTextureStorageMode == .managed, let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.synchronize(resource: outputTexture)
            blitEncoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw error
        }

        return try image(from: outputTexture)
    }

    static func assertVisualMatch(
        _ image: RGBAImage,
        reference referenceLocation: ReferenceImageLocation,
        threshold: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if isRecordingReferences {
            try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true, attributes: nil)
            try writePNG(image, to: referenceDirectory.appendingPathComponent(referenceLocation.filename))
            return
        }

        guard let referenceURL = referenceLocation.url else {
            XCTFail("Missing reference image: \(referenceLocation.filename)", file: file, line: line)
            return
        }

        let reference = try loadImage(at: referenceURL)
        XCTAssertEqual(image.width, reference.width, "Rendered image width differs from reference", file: file, line: line)
        XCTAssertEqual(image.height, reference.height, "Rendered image height differs from reference", file: file, line: line)

        let diff = diff(rendered: image, reference: reference)
        if diff.meanAbsoluteDifference > threshold {
            try FileManager.default.createDirectory(at: failureArtifactsDirectory, withIntermediateDirectories: true, attributes: nil)

            let stem = referenceLocation.filename.replacingOccurrences(of: ".png", with: "")
            let actualURL = failureArtifactsDirectory.appendingPathComponent("\(stem)-actual.png")
            let diffURL = failureArtifactsDirectory.appendingPathComponent("\(stem)-diff.png")

            try writePNG(image, to: actualURL)
            try writePNG(diff.diffImage, to: diffURL)

            XCTFail(
                """
                Visual diff exceeded threshold for \(referenceLocation.filename)
                meanAbsoluteDifference: \(diff.meanAbsoluteDifference)
                threshold: \(threshold)
                maxAbsoluteDifference: \(diff.maxAbsoluteDifference)
                differingPixels: \(diff.differingPixelCount)/\(diff.totalPixelCount)
                actual: \(actualURL.path)
                diff: \(diffURL.path)
                """,
                file: file,
                line: line
            )
        }
    }

    static func assertContainsVisibleContent(
        _ image: RGBAImage,
        minimumChangedPixelRatio: Double = 0.01,
        minimumMeanNormalizedDifference: Double = 0.002,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let coverage = contentCoverage(image)
        if coverage.changedPixelRatio < minimumChangedPixelRatio || coverage.meanNormalizedDifference < minimumMeanNormalizedDifference {
            XCTFail(
                """
                Render appears empty or too close to the clear color
                changedPixelRatio: \(coverage.changedPixelRatio)
                minimumChangedPixelRatio: \(minimumChangedPixelRatio)
                meanNormalizedDifference: \(coverage.meanNormalizedDifference)
                minimumMeanNormalizedDifference: \(minimumMeanNormalizedDifference)
                """,
                file: file,
                line: line
            )
        }
    }

    static func assertContainsVisibleContent(
        _ image: RGBAImage,
        in region: ImageRegion,
        minimumChangedPixelRatio: Double = 0.01,
        minimumMeanNormalizedDifference: Double = 0.002,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let coverage = contentCoverage(image, in: region.normalizedRect)
        if coverage.changedPixelRatio < minimumChangedPixelRatio || coverage.meanNormalizedDifference < minimumMeanNormalizedDifference {
            XCTFail(
                """
                Render appears empty or too close to the clear color in region \(region.name)
                changedPixelRatio: \(coverage.changedPixelRatio)
                minimumChangedPixelRatio: \(minimumChangedPixelRatio)
                meanNormalizedDifference: \(coverage.meanNormalizedDifference)
                minimumMeanNormalizedDifference: \(minimumMeanNormalizedDifference)
                """,
                file: file,
                line: line
            )
        }
    }

    static func loadImage(at url: URL) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(domain: "VisualTestHarness", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to load image at \(url.path)"])
        }

        return try image(from: cgImage)
    }

    static func image(from texture: MTLTexture) throws -> RGBAImage {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bgraPixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        texture.getBytes(
            &bgraPixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        var rgbaPixels = [UInt8](repeating: 0, count: bgraPixels.count)
        for index in stride(from: 0, to: bgraPixels.count, by: 4) {
            rgbaPixels[index + 0] = bgraPixels[index + 2]
            rgbaPixels[index + 1] = bgraPixels[index + 1]
            rgbaPixels[index + 2] = bgraPixels[index + 0]
            rgbaPixels[index + 3] = bgraPixels[index + 3]
        }

        return RGBAImage(width: width, height: height, pixels: rgbaPixels)
    }

    static func image(from cgImage: CGImage) throws -> RGBAImage {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "VisualTestHarness", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap context"])
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func diff(rendered: RGBAImage, reference: RGBAImage) -> VisualDiffResult {
        let pixelCount = min(rendered.width * rendered.height, reference.width * reference.height)
        let sampleCount = pixelCount * 4
        var diffPixels = [UInt8](repeating: 0, count: pixelCount * 4)
        var totalDifference = 0
        var maxDifference = 0
        var differingPixels = 0

        for pixelIndex in 0..<pixelCount {
            let base = pixelIndex * 4
            var pixelMaxDifference = 0

            for channel in 0..<4 {
                let difference = abs(Int(rendered.pixels[base + channel]) - Int(reference.pixels[base + channel]))
                totalDifference += difference
                pixelMaxDifference = max(pixelMaxDifference, difference)
                maxDifference = max(maxDifference, difference)
            }

            if pixelMaxDifference > 0 {
                differingPixels += 1
            }

            diffPixels[base + 0] = UInt8(pixelMaxDifference)
            diffPixels[base + 1] = 0
            diffPixels[base + 2] = 0
            diffPixels[base + 3] = 255
        }

        return VisualDiffResult(
            meanAbsoluteDifference: Double(totalDifference) / Double(sampleCount * 255),
            maxAbsoluteDifference: UInt8(maxDifference),
            differingPixelCount: differingPixels,
            totalPixelCount: pixelCount,
            diffImage: RGBAImage(width: rendered.width, height: rendered.height, pixels: diffPixels)
        )
    }

    static func contentCoverage(_ image: RGBAImage) -> ContentCoverageResult {
        contentCoverage(image, in: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0))
    }

    static func contentCoverage(_ image: RGBAImage, in normalizedRect: CGRect) -> ContentCoverageResult {
        let clearColor = rgbaBytes(for: defaultClearColor)
        let x0 = max(0, min(image.width, Int(floor(normalizedRect.minX * Double(image.width)))))
        let y0 = max(0, min(image.height, Int(floor(normalizedRect.minY * Double(image.height)))))
        let x1 = max(x0 + 1, min(image.width, Int(ceil(normalizedRect.maxX * Double(image.width)))))
        let y1 = max(y0 + 1, min(image.height, Int(ceil(normalizedRect.maxY * Double(image.height)))))
        let pixelCount = (x1 - x0) * (y1 - y0)
        var changedPixelCount = 0
        var totalDifference = 0

        for y in y0..<y1 {
            for x in x0..<x1 {
                let base = (y * image.width + x) * 4
                var pixelDifference = 0

                for channel in 0..<4 {
                    pixelDifference += abs(Int(image.pixels[base + channel]) - Int(clearColor[channel]))
                }

                totalDifference += pixelDifference
                if pixelDifference > 4 {
                    changedPixelCount += 1
                }
            }
        }

        return ContentCoverageResult(
            changedPixelCount: changedPixelCount,
            totalPixelCount: pixelCount,
            changedPixelRatio: Double(changedPixelCount) / Double(pixelCount),
            meanNormalizedDifference: Double(totalDifference) / Double(pixelCount * 4 * 255)
        )
    }

    static func writePNG(_ image: RGBAImage, to url: URL) throws {
        let bytesPerRow = image.width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let cgImage = CGImage(
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "VisualTestHarness", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "VisualTestHarness", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG to \(url.path)"])
        }
    }

    private static var readableTextureStorageMode: MTLStorageMode {
        #if arch(x86_64)
        return .managed
        #else
        return .shared
        #endif
    }

    private static func rgbaBytes(for color: simd_float4) -> [UInt8] {
        [
            UInt8(max(0, min(255, Int((color.x * 255.0).rounded())))),
            UInt8(max(0, min(255, Int((color.y * 255.0).rounded())))),
            UInt8(max(0, min(255, Int((color.z * 255.0).rounded())))),
            UInt8(max(0, min(255, Int((color.w * 255.0).rounded()))))
        ]
    }
}
