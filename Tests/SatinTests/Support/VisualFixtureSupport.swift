import Metal
import Satin
import simd

enum VisualFixtureSupport {
    private static var retainedTextures: [String: [MTLTexture]] = [:]

    static func retain(_ textures: [MTLTexture], for key: String) {
        retainedTextures[key] = textures
    }

    static func makeSolidTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        let pixels: [UInt8] = [
            255, 255, 255, 255, 200, 100, 50, 255,
            50, 180, 220, 255, 20, 20, 20, 255,
        ]
        texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
        return texture
    }

    static func makeCheckerTexture(device: MTLDevice, width: Int = 32, height: Int = 32) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let tile = ((x / 8) + (y / 8)) % 2
                let base: UInt8 = tile == 0 ? 235 : 45
                pixels[index + 0] = base
                pixels[index + 1] = tile == 0 ? 120 : 210
                pixels[index + 2] = tile == 0 ? 60 : 180
                pixels[index + 3] = 255
            }
        }

        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    static func makeAlphaTexture(device: MTLDevice, width: Int = 32, height: Int = 32) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let dx = Float(x - width / 2) / Float(width / 2)
                let dy = Float(y - height / 2) / Float(height / 2)
                let radius = sqrt(dx * dx + dy * dy)
                let alpha = UInt8(max(0.0, min(1.0, 1.0 - radius)) * 255.0)
                pixels[index + 0] = 255
                pixels[index + 1] = 255
                pixels[index + 2] = 255
                pixels[index + 3] = alpha
            }
        }

        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }


    static func makeCubeTexture(device: MTLDevice, size: Int = 8) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm, size: size, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        let bytesPerRow = size * 4
        let bytesPerImage = size * size * 4

        let colors: [[UInt8]] = [
            [240, 90, 80, 255],
            [80, 200, 120, 255],
            [70, 140, 240, 255],
            [250, 210, 80, 255],
            [180, 100, 240, 255],
            [70, 220, 220, 255],
        ]

        for slice in 0..<6 {
            var pixels = [UInt8](repeating: 0, count: size * size * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index + 0] = colors[slice][0]
                pixels[index + 1] = colors[slice][1]
                pixels[index + 2] = colors[slice][2]
                pixels[index + 3] = 255
            }

            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                slice: slice,
                withBytes: pixels,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }

        return texture
    }

    static func makeFontAtlas() -> FontAtlas {
        let json = """
        {
          "name": "TestAtlas",
          "size": 16,
          "bold": false,
          "italic": false,
          "width": 64,
          "height": 64,
          "characters": {
            "S": { "x": 0, "y": 0, "width": 16, "height": 16, "originX": 0, "originY": 0, "advance": 16 },
            "A": { "x": 16, "y": 0, "width": 16, "height": 16, "originX": 0, "originY": 0, "advance": 16 },
            "T": { "x": 32, "y": 0, "width": 16, "height": 16, "originX": 0, "originY": 0, "advance": 16 },
            "I": { "x": 48, "y": 0, "width": 8, "height": 16, "originX": 0, "originY": 0, "advance": 8 },
            "N": { "x": 0, "y": 16, "width": 16, "height": 16, "originX": 0, "originY": 0, "advance": 16 }
          }
        }
        """
        return try! JSONDecoder().decode(FontAtlas.self, from: Data(json.utf8))
    }

    static func makeFontTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)

        fillGlyphRect(&pixels, width: 64, originX: 0, originY: 0, glyphWidth: 16, glyphHeight: 16, color: [255, 240, 120, 255])
        fillGlyphRect(&pixels, width: 64, originX: 16, originY: 0, glyphWidth: 16, glyphHeight: 16, color: [120, 220, 255, 255])
        fillGlyphRect(&pixels, width: 64, originX: 32, originY: 0, glyphWidth: 16, glyphHeight: 16, color: [255, 150, 120, 255])
        fillGlyphRect(&pixels, width: 64, originX: 48, originY: 0, glyphWidth: 8, glyphHeight: 16, color: [200, 255, 140, 255])
        fillGlyphRect(&pixels, width: 64, originX: 0, originY: 16, glyphWidth: 16, glyphHeight: 16, color: [255, 255, 255, 255])

        texture.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 64 * 4)
        return texture
    }

    private static func fillGlyphRect(_ pixels: inout [UInt8], width: Int, originX: Int, originY: Int, glyphWidth: Int, glyphHeight: Int, color: [UInt8]) {
        for y in originY..<(originY + glyphHeight) {
            for x in originX..<(originX + glyphWidth) {
                let index = (y * width + x) * 4
                pixels[index + 0] = color[0]
                pixels[index + 1] = color[1]
                pixels[index + 2] = color[2]
                pixels[index + 3] = color[3]
            }
        }
    }
}
