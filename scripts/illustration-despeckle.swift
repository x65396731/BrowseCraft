// 去噪点：清掉透明底插画里与主体不相连的小色块（抠图残留，深色底上显成白点），再按保留部分裁掉左右透明边。
// 用法：swift scripts/illustration-despeckle.swift <输入.png> <输出.png> <最小保留面积px> [保留区域 x0,y0,x1,y1]
// 面积小于阈值的连通块（alpha > 8，八邻接）清零；外接框中心落在保留区域里的小块不清（画面里故意画的火花、光点）。
// 只裁左右、不裁上下：插画按固定高度显示，高度不变才不改变显示大小。
import AppKit
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let minArea = Int(a[3])!
let keep: CGRect? = a.count > 4 ? { let v = a[4].split(separator: ",").map { CGFloat(Double($0)!) }; return CGRect(x: v[0], y: v[1], width: v[2]-v[0], height: v[3]-v[1]) }() : nil
let w = image.width, h = image.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w*h*4)
let threshold: UInt8 = 8
var label = [Int32](repeating: -1, count: w*h)
var sizes: [Int] = []; var members: [[Int]] = []; var centers: [CGPoint] = []
for s in 0..<(w*h) where px[s*4+3] > threshold && label[s] < 0 {
    let id = Int32(sizes.count); var stack = [s]; label[s] = id; var m: [Int] = []
    while let p = stack.popLast() {
        m.append(p); let x = p % w, y = p / w
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x+dx, ny = y+dy
            if nx >= 0, ny >= 0, nx < w, ny < h { let q = ny*w+nx; if px[q*4+3] > threshold && label[q] < 0 { label[q] = id; stack.append(q) } }
        } }
    }
    sizes.append(m.count); members.append(m)
    let xs = m.map { $0 % w }, ys = m.map { $0 / w }
    centers.append(CGPoint(x: CGFloat(xs.min()! + xs.max()!) / 2, y: CGFloat(ys.min()! + ys.max()!) / 2))
}
var removed = 0
func kept(_ i: Int) -> Bool { return sizes[i] >= minArea || (keep?.contains(centers[i]) ?? false) }
for (i, m) in members.enumerated() where kept(i) == false {
    for p in m { for k in 0..<4 { px[p*4+k] = 0 } }; removed += 1
}
// 主体外接框以外、alpha 极低的残余像素一并清零，保证裁边贴着主体。
var minX = w, minY = h, maxX = 0, maxY = 0
for (i, m) in members.enumerated() where kept(i) {
    for p in m { let x = p % w, y = p / w; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
}
for y in 0..<h { for x in 0..<w where x < minX || x > maxX { for k in 0..<4 { px[(y*w+x)*4+k] = 0 } } }
let full = ctx.makeImage()!
// CGImage 的坐标原点在左上，bitmap 行序与 makeImage 一致。
// 只裁左右：插画按固定高度显示，高度不变才不改变显示大小。
let cropped = full.cropping(to: CGRect(x: minX, y: 0, width: maxX-minX+1, height: h))!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cropped, nil); CGImageDestinationFinalize(dest)
print("removed \(removed) specks; kept \(sizes.indices.filter(kept).count) part(s); crop x \(minX)..<\(maxX + 1) → \(cropped.width)x\(cropped.height)")
