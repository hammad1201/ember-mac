// Renders docs/social-card.png (1600×900): logo, name, tagline and the real dashboard screenshot.
// Usage: swift Scripts/make_card.swift docs/icon.png docs/dashboard.jpg docs/social-card.png
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let shot = NSImage(contentsOfFile: args[2])!
let out = args[3]

let W = 1600, H = 900
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let canvas = NSRect(x: 0, y: 0, width: W, height: H)

// Background: deep wine with a rose bloom behind the screenshot.
NSGradient(colors: [rgb(0.16, 0.02, 0.07), rgb(0.30, 0.04, 0.11), rgb(0.42, 0.07, 0.16)])!.draw(in: canvas, angle: 20)
NSGradient(colors: [rgb(0.88, 0.38, 0.50, 0.45), rgb(0.88, 0.38, 0.50, 0)])!
    .draw(fromCenter: NSPoint(x: 1150, y: 420), radius: 0, toCenter: NSPoint(x: 1150, y: 420), radius: 700, options: [])
NSGradient(colors: [rgb(0.95, 0.80, 0.58, 0.18), rgb(0.95, 0.80, 0.58, 0)])!
    .draw(fromCenter: NSPoint(x: 220, y: 760), radius: 0, toCenter: NSPoint(x: 220, y: 760), radius: 420, options: [])

// Screenshot on the right, rounded, with a soft shadow, bleeding off the edge.
let shotRect = NSRect(x: 690, y: -60, width: 1040, height: 1040 * shot.size.height / shot.size.width)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: NSColor.black.withAlphaComponent(0.55).cgColor)
NSColor.black.setFill()
NSBezierPath(roundedRect: shotRect, xRadius: 26, yRadius: 26).fill()
ctx.restoreGState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: shotRect, xRadius: 26, yRadius: 26).addClip()
shot.draw(in: shotRect)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.18).setStroke()
let border = NSBezierPath(roundedRect: shotRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 26, yRadius: 26)
border.lineWidth = 1.5
border.stroke()

// Left column: icon, name, tagline, details.
icon.draw(in: NSRect(x: 72, y: 560, width: 220, height: 220))

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0, serif: Bool = false) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if serif, let d = font.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { font = f }
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}

let blush = rgb(0.97, 0.70, 0.76), champagne = rgb(0.95, 0.80, 0.58)
draw("Ember", at: NSPoint(x: 86, y: 430), size: 112, weight: .bold, color: .white, kern: -2)
draw("See what's heating", at: NSPoint(x: 90, y: 360), size: 44, weight: .regular, color: blush, serif: true)
draw("your Mac.", at: NSPoint(x: 90, y: 306), size: 44, weight: .regular, color: blush, serif: true)

let bullets = ["Chip temps, fans & live power", "Which apps are burning energy", "Menu bar + desktop widget"]
for (i, b) in bullets.enumerated() {
    let y = CGFloat(228 - i * 42)
    champagne.setFill()
    NSBezierPath(ovalIn: NSRect(x: 92, y: y + 9, width: 9, height: 9)).fill()
    draw(b, at: NSPoint(x: 114, y: y), size: 24, weight: .medium, color: NSColor.white.withAlphaComponent(0.88))
}

// Open-source pill.
let pill = NSRect(x: 88, y: 52, width: 420, height: 50)
rgb(0.95, 0.80, 0.58, 0.16).setFill()
NSBezierPath(roundedRect: pill, xRadius: 25, yRadius: 25).fill()
champagne.withAlphaComponent(0.5).setStroke()
let pillBorder = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 25, yRadius: 25)
pillBorder.lineWidth = 1
pillBorder.stroke()
draw("Free & open source · MIT", at: NSPoint(x: 112, y: 63), size: 22, weight: .semibold, color: champagne)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
