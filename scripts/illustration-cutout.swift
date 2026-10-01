// 抠图：Vision 前景实例蒙版（所有实例合并）→ 透明底 PNG → 裁掉透明边 → 缩放到指定高度。
// 用法：swift scripts/illustration-cutout.swift <输入> <输出.png> <目标高度px>
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 4, let targetHeight = Double(args[3]) else {
    fputs("usage: illustration-cutout <in> <out.png> <height>\n", stderr); exit(2)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let source = CIImage(contentsOf: inputURL) else { fputs("cannot read input\n", stderr); exit(1) }
let handler = VNImageRequestHandler(ciImage: source)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first else { fputs("no foreground found\n", stderr); exit(1) }
let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
let mask = CIImage(cvPixelBuffer: maskBuffer)

let clear = CIImage(color: .clear).cropped(to: source.extent)
guard let blend = CIFilter(name: "CIBlendWithMask") else { exit(1) }
blend.setValue(source, forKey: kCIInputImageKey)
blend.setValue(clear, forKey: kCIInputBackgroundImageKey)
blend.setValue(mask, forKey: kCIInputMaskImageKey)
guard let cut = blend.outputImage else { exit(1) }

let context = CIContext()
guard let cgFull = context.createCGImage(cut, from: source.extent) else { exit(1) }

// 透明边界：alpha > 8 的最小外接矩形，四周留 2% 余量。
let width = cgFull.width, height = cgFull.height
let space = CGColorSpaceCreateDeviceRGB()
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let bitmap = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.draw(cgFull, in: CGRect(x: 0, y: 0, width: width, height: height))
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let pad = Int(Double(max(maxX - minX, maxY - minY)) * 0.02)
let crop = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                  width: min(width, maxX + pad + 1) - max(0, minX - pad),
                  height: min(height, maxY + pad + 1) - max(0, minY - pad))
guard let trimmed = cgFull.cropping(to: crop) else { exit(1) }

// 缩放到目标高度。
let scale = targetHeight / Double(trimmed.height)
let outW = Int((Double(trimmed.width) * scale).rounded()), outH = Int(targetHeight)
let out = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .high
out.draw(trimmed, in: CGRect(x: 0, y: 0, width: outW, height: outH))
let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: outputURL)
print("\(outW)x\(outH) instances=\(observation.allInstances.count)")
