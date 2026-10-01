// 横幅：整张图等比缩到目标高度、靠右放，左侧用原图左缘的平均色补齐，接缝渐变过渡。
// 用法：swift scripts/illustration-banner.swift <输入> <输出.png> <宽> <高> [接缝过渡宽度px，默认 140] [右侧留白px，默认 0]
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 5, let outW = Double(args[3]), let outH = Double(args[4]) else {
    fputs("usage: illustration-banner <in> <out.png> <w> <h> [fade]\n", stderr); exit(2)
}
let fade = args.count >= 6 ? Double(args[5]) ?? 140 : 140
let rightPad = args.count >= 7 ? Double(args[6]) ?? 0 : 0
guard let source = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else { fputs("cannot read\n", stderr); exit(1) }

let scale = outH / source.extent.height
let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let offsetX = outW - scaled.extent.width - rightPad
let placed = scaled.transformed(by: CGAffineTransform(translationX: offsetX, y: 0))
let canvas = CGRect(x: 0, y: 0, width: outW, height: outH)

// 原图左缘 10% 宽的平均色作为补齐色。
let edge = CGRect(x: 0, y: 0, width: source.extent.width * 0.1, height: source.extent.height)
let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: source, kCIInputExtentKey: CIVector(cgRect: edge)])!.outputImage!
var rgba = [UInt8](repeating: 0, count: 4)
let context = CIContext()
context.render(average, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
let fill = CIImage(color: CIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255))
    .cropped(to: canvas)

let mask = CIFilter(name: "CILinearGradient", parameters: [
    "inputPoint0": CIVector(x: max(0, offsetX), y: 0), "inputColor0": CIColor(red: 0, green: 0, blue: 0),
    "inputPoint1": CIVector(x: max(0, offsetX) + fade, y: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
])!.outputImage!.cropped(to: canvas)
// 右侧留白时，图像右缘同样渐变进补齐色（40px）。
let rightEdge = offsetX + scaled.extent.width
let rightMask = rightPad > 0 ? CIFilter(name: "CILinearGradient", parameters: [
    "inputPoint0": CIVector(x: rightEdge - 40, y: 0), "inputColor0": CIColor(red: 1, green: 1, blue: 1),
    "inputPoint1": CIVector(x: rightEdge, y: 0), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
])!.outputImage!.cropped(to: canvas) : nil
let combinedMask = rightMask.map { CIFilter(name: "CIMultiplyCompositing", parameters: [kCIInputImageKey: mask, kCIInputBackgroundImageKey: $0])!.outputImage!.cropped(to: canvas) } ?? mask
let blended = CIFilter(name: "CIBlendWithMask", parameters: [
    kCIInputImageKey: placed.cropped(to: canvas), kCIInputBackgroundImageKey: fill, kCIInputMaskImageKey: combinedMask,
])!.outputImage!

guard let cg = context.createCGImage(blended, from: canvas) else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("\(Int(outW))x\(Int(outH)) fill=#\(String(format: "%02X%02X%02X", rgba[0], rgba[1], rgba[2])) imageWidth=\(Int(scaled.extent.width))")
