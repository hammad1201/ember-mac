// Draws the 1024px app icon: burgundy squircle, champagne-to-rose gauge arc, white thermometer.
import AppKit

let out = CommandLine.arguments[1]
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let champagne = rgb(0.96, 0.82, 0.60)
let rose = rgb(0.92, 0.42, 0.54)
let crimson = rgb(0.93, 0.18, 0.26)

// macOS icon grid: 824pt body centred in 1024, with room for the drop shadow.
let body = NSRect(x: 100, y: 110, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Body: deep wine at the bottom rising to burgundy, with a soft rose bloom up top.
NSGradient(colors: [rgb(0.20, 0.03, 0.08), rgb(0.42, 0.06, 0.15), rgb(0.62, 0.12, 0.24)])!
    .draw(in: shape, angle: 90)
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [rose.withAlphaComponent(0.55), rose.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: body.midX, y: body.maxY - 60), radius: 0,
          toCenter: NSPoint(x: body.midX, y: body.maxY - 60), radius: 520, options: [])
// Glassy top highlight.
NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.16)])!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: 90)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.14).setStroke()
shape.lineWidth = 4
shape.stroke()

// Gauge: 270° arc opening at the bottom, track plus a filled section.
let center = NSPoint(x: body.midX, y: body.midY - 6)
let radius: CGFloat = 270
let lineWidth: CGFloat = 50
func arc(from start: CGFloat, to end: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    p.lineWidth = lineWidth
    p.lineCapStyle = .round
    return p
}
NSColor.white.withAlphaComponent(0.13).setStroke()
arc(from: 225, to: -45).stroke()

// Fill ~70% of the arc with a champagne → rose → crimson sweep, drawn as short segments.
let startAngle: CGFloat = 225, sweep: CGFloat = 270 * 0.70
let steps = 120
for i in 0..<steps {
    let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
    let color = t0 < 0.5
        ? champagne.blended(withFraction: t0 * 2, of: rose)!
        : rose.blended(withFraction: (t0 - 0.5) * 2, of: crimson)!
    color.setStroke()
    let seg = arc(from: startAngle - sweep * t0, to: startAngle - sweep * t1 - 0.6)
    seg.lineCapStyle = (i == 0 || i == steps - 1) ? .round : .butt
    seg.stroke()
}

// Thermometer in the middle.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
