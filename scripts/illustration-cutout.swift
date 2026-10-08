// 抠图：Vision 前景实例蒙版（所有实例合并）→ 透明底 PNG → 裁掉透明边 → 缩放到指定高度。
// 用法：swift scripts/illustration-cutout.swift <输入> <输出.png> <目标高度px> [近白阈值]
// 给了近白阈值（如 236）时，蒙版之后再从透明像素出发，向相连的近白像素（三通道都 ≥ 阈值、色差 ≤ 14）洪水填充清成透明，
// 去掉 Vision 留在发丝外沿的白底；角色身上的白色有深色轮廓线围着，填充进不去。
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 4 || args.count == 5, let targetHeight = Double(args[3]) else {
    fputs("usage: illustration-cutout <in> <out.png> <height> [near-white-threshold]\n", stderr); exit(2)
}
let whiteThreshold: Int? = args.count == 5 ? Int(args[4]) : nil
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
guard var cgFull = context.createCGImage(cut, from: source.extent) else { exit(1) }

// 可选：从透明像素向相连的近白像素洪水填充，清成透明。
if let threshold = whiteThreshold {
    let w = cgFull.width, h = cgFull.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cgFull, in: CGRect(x: 0, y: 0, width: w, height: h))
    func nearWhite(_ i: Int) -> Bool {
        let a = Int(px[i * 4 + 3]); if a == 0 { return true }
        let r = Int(px[i * 4]) * 255 / a, g = Int(px[i * 4 + 1]) * 255 / a, b = Int(px[i * 4 + 2]) * 255 / a
        return min(r, g, b) >= threshold && max(r, g, b) - min(r, g, b) <= 14
    }
    var seen = [Bool](repeating: false, count: w * h)
    var stack = [Int]()
    for i in 0..<(w * h) where px[i * 4 + 3] < 128 { seen[i] = true; stack.append(i) }
    var cleared = 0
    while let i = stack.popLast() {
        if px[i * 4 + 3] != 0 { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0; cleared += 1 }
        let x = i % w, y = i / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let j = ny * w + nx
            if !seen[j] && nearWhite(j) { seen[j] = true; stack.append(j) }
        }
    }
    fputs("cleared \(cleared) near-white px\n", stderr)
    cgFull = ctx.makeImage()!
}

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
