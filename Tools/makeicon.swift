import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}

// Rounded-rect path helper
func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1) Background diagonal gradient (indigo -> blue)
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(58, 110, 246), rgb(20, 41, 156)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// soft glow top-left
let glow = CGGradient(colorsSpace: cs,
                      colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 760), endRadius: 620, options: [])

// 2) Newspaper / document card, slightly rotated
ctx.saveGState()
ctx.translateBy(x: S/2, y: S/2)
ctx.rotate(by: -7 * .pi / 180)
let cardW: CGFloat = 540, cardH: CGFloat = 660
let card = CGRect(x: -cardW/2, y: -cardH/2, width: cardW, height: cardH)

// shadow
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 50, color: rgb(10, 20, 70, 0.45))
ctx.addPath(roundedRect(card, 46))
ctx.setFillColor(rgb(255, 255, 255))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// headline block (accent)
let pad: CGFloat = 56
ctx.addPath(roundedRect(CGRect(x: card.minX + pad, y: card.maxY - pad - 70,
                               width: cardW - pad*2, height: 70), 16))
ctx.setFillColor(rgb(20, 41, 156))
ctx.fillPath()

// text lines (light gray), varied widths
let lineColor = rgb(203, 211, 230)
let lineH: CGFloat = 34
let gap: CGFloat = 30
let widths: [CGFloat] = [1.0, 0.86, 0.93, 0.7, 0.9, 0.6]
var y = card.maxY - pad - 70 - 64
for w in widths {
    ctx.addPath(roundedRect(CGRect(x: card.minX + pad, y: y,
                                   width: (cardW - pad*2) * w, height: lineH), 10))
    ctx.setFillColor(lineColor)
    ctx.fillPath()
    y -= (lineH + gap)
}
ctx.restoreGState()

// 3) Magnifying glass over lower-right
let center = CGPoint(x: 660, y: 405)
let ringR: CGFloat = 196
let ringW: CGFloat = 56

// lens fill (subtle tint + accent scan highlight inside)
ctx.saveGState()
ctx.addPath(CGPath(ellipseIn: CGRect(x: center.x - ringR, y: center.y - ringR,
                                     width: ringR*2, height: ringR*2), transform: nil))
ctx.clip()
ctx.setFillColor(rgb(20, 41, 156, 0.10))
ctx.fill(CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR*2, height: ringR*2))
// accent "scan" bar inside lens
ctx.addPath(roundedRect(CGRect(x: center.x - 120, y: center.y - 18, width: 240, height: 36), 18))
ctx.setFillColor(rgb(255, 159, 28))
ctx.fillPath()
ctx.restoreGState()

// handle (drawn before ring so the ring caps it cleanly)
let hStart = CGPoint(x: center.x + cos(-0.785) * ringR, y: center.y + sin(-0.785) * ringR)
let hEnd = CGPoint(x: hStart.x + 150, y: hStart.y - 150)
ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(255, 255, 255))
ctx.setLineWidth(64)
ctx.move(to: hStart); ctx.addLine(to: hEnd); ctx.strokePath()

// ring
ctx.setStrokeColor(rgb(255, 255, 255))
ctx.setLineWidth(ringW)
ctx.addEllipse(in: CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR*2, height: ringR*2))
ctx.strokePath()
// inner thin ring for depth
ctx.setStrokeColor(rgb(20, 41, 156, 0.25))
ctx.setLineWidth(8)
let r2 = ringR - ringW/2 - 6
ctx.addEllipse(in: CGRect(x: center.x - r2, y: center.y - r2, width: r2*2, height: r2*2))
ctx.strokePath()

// Save PNG
guard let img = ctx.makeImage() else { fatalError("img") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
