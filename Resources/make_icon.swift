// Renders the Haze logo assets. Usage: swift make_icon.swift <outdir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let cs = CGColorSpaceCreateDeviceRGB()
func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

/// Draws the mark into a 1024×1024 space (CoreGraphics, y-up).
func drawMark(_ ctx: CGContext, shadow: Bool = true) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0x0B1220, 0.28))
        ctx.addPath(squircle); ctx.setFillColor(c(0xA9C8CC)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let lin = CGGradient(colorsSpace: cs, colors: [c(0x5E9AA8), c(0x9CC2C7), c(0xE6C2AE)] as CFArray, locations: [0, 0.52, 1])!
    ctx.drawLinearGradient(lin, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    let glow = CGGradient(colorsSpace: cs, colors: [c(0xFFFFFF, 0.6), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 290, y: 760), startRadius: 0, endCenter: CGPoint(x: 290, y: 760), endRadius: 440, options: [])
    let peach = CGGradient(colorsSpace: cs, colors: [c(0xF4C2A4, 0.85), c(0xF4C2A4, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(peach, startCenter: CGPoint(x: 800, y: 210), startRadius: 0, endCenter: CGPoint(x: 800, y: 210), endRadius: 430, options: [])
    // frosted plate
    let plate = CGPath(roundedRect: CGRect(x: 232, y: 232, width: 560, height: 560), cornerWidth: 150, cornerHeight: 150, transform: nil)
    ctx.addPath(plate); ctx.setFillColor(c(0xFFFFFF, 0.26)); ctx.fillPath()
    ctx.addPath(plate); ctx.setStrokeColor(c(0xFFFFFF, 0.85)); ctx.setLineWidth(4); ctx.strokePath()
    // lowercase "h": ink shoulder + leg (an event card turning the corner), white stem on top
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x15203A, 0.2))
    let shoulder = CGMutablePath()
    shoulder.addArc(center: CGPoint(x: 512, y: 470), radius: 94, startAngle: .pi, endAngle: 0, clockwise: true)
    shoulder.addLine(to: CGPoint(x: 606, y: 386))
    ctx.addPath(shoulder)
    ctx.setStrokeColor(c(0x15203A)); ctx.setLineWidth(112); ctx.setLineCap(.round); ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 362, y: 330, width: 112, height: 400), cornerWidth: 56, cornerHeight: 56, transform: nil))
    ctx.setFillColor(c(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    // rising sun
    let sun = CGGradient(colorsSpace: cs, colors: [c(0xF7B38E), c(0xEE8F6E)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: 618, y: 628, width: 80, height: 80)); ctx.clip()
    ctx.drawLinearGradient(sun, start: CGPoint(x: 658, y: 708), end: CGPoint(x: 658, y: 628), options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

func png(_ w: Int, _ h: Int, _ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func wordmark(_ ctx: CGContext, x: CGFloat, baseline: CGFloat, size: CGFloat, color: CGColor) {
    let font = NSFont(name: "AvenirNext-Medium", size: size)!
    let str = NSAttributedString(string: "haze", attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: -size * 0.035])
    let line = CTLineCreateWithAttributedString(str)
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line, ctx)
}

// 1. App icon / mark
png(1024, 1024, "haze-icon.png") { drawMark($0) }

// 2. Horizontal logo, for light and dark backgrounds
for (name, color) in [("haze-logo.png", c(0x15203A)), ("haze-logo-white.png", c(0xFFFFFF))] {
    png(1500, 520, name) { ctx in
        ctx.saveGState()
        ctx.translateBy(x: 20, y: 20); ctx.scaleBy(x: 480 / 1024, y: 480 / 1024)
        drawMark(ctx, shadow: false)
        ctx.restoreGState()
        wordmark(ctx, x: 520, baseline: 150, size: 300, color: color)
    }
}
