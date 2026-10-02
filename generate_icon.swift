import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                              bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let background = NSGradient(starting: NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.27, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.48, blue: 0.70, alpha: 1))!
background.draw(in: canvas, angle: -40)
let band = NSBezierPath(roundedRect: NSRect(x: 382, y: 118, width: 260, height: 788), xRadius: 100, yRadius: 100)
NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
band.fill()
let caseOutline = NSBezierPath(roundedRect: NSRect(x: 278, y: 242, width: 468, height: 540), xRadius: 138, yRadius: 138)
NSColor.white.setFill()
caseOutline.fill()
let screen = NSBezierPath(roundedRect: NSRect(x: 312, y: 277, width: 400, height: 470), xRadius: 110, yRadius: 110)
NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.23, alpha: 1).setFill()
screen.fill()
let crown = NSBezierPath(roundedRect: NSRect(x: 737, y: 512, width: 43, height: 105), xRadius: 14, yRadius: 14)
NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
crown.fill()
let text = "26" as NSString
let font = NSFont.systemFont(ofSize: 195, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let textSize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: 512 - textSize.width / 2, y: 512 - textSize.height / 2 - 12), withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
for name in ["square.png", "square-dark 1.png", "out.png"] {
    let url = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/" + name)
    try png.write(to: url)
}
