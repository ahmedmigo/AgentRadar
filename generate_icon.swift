import Cocoa

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let context = NSGraphicsContext.current!.cgContext
let rect = CGRect(origin: .zero, size: size)

// Draw background
let path = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
path.addClip()

// Gradient background
let colors = [
    NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0).cgColor,
    NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

let center = CGPoint(x: size.width/2, y: size.height/2)

// Draw Radar Circles
context.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.3).cgColor)
context.setLineWidth(12)

for radius in stride(from: 150, to: 450, by: 100) {
    let circlePath = CGPath(ellipseIn: CGRect(x: center.x - CGFloat(radius), y: center.y - CGFloat(radius), width: CGFloat(radius*2), height: CGFloat(radius*2)), transform: nil)
    context.addPath(circlePath)
    context.strokePath()
}

// Draw sweeping radar beam
context.move(to: center)
context.addLine(to: CGPoint(x: center.x, y: center.y + 450))
context.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.8).cgColor)
context.setLineWidth(10)
context.strokePath()

// Draw sweep gradient
context.saveGState()
context.move(to: center)
context.addLine(to: CGPoint(x: center.x, y: center.y + 450))
context.addArc(center: center, radius: 450, startAngle: .pi/2, endAngle: .pi/4, clockwise: true)
context.closePath()
context.clip()

let sweepColors = [
    NSColor.systemGreen.withAlphaComponent(0.5).cgColor,
    NSColor.systemGreen.withAlphaComponent(0.0).cgColor
] as CFArray
let sweepGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sweepColors, locations: [0, 1])!
context.drawLinearGradient(sweepGradient, start: CGPoint(x: center.x, y: center.y + 450), end: CGPoint(x: center.x + 450, y: center.y), options: [])
context.restoreGState()

// Draw Terminal Box Background at center
let terminalRect = CGRect(x: center.x - 160, y: center.y - 120, width: 320, height: 240)
let terminalPath = NSBezierPath(roundedRect: terminalRect, xRadius: 32, yRadius: 32)
NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.95).setFill()
terminalPath.fill()

NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0).setStroke()
terminalPath.lineWidth = 8
terminalPath.stroke()

// Draw Terminal prompt ">_"
context.setStrokeColor(NSColor.systemGreen.cgColor)
context.setLineWidth(32)
context.setLineCap(.round)
context.setLineJoin(.round)

// Draw '>'
context.move(to: CGPoint(x: center.x - 80, y: center.y + 40))
context.addLine(to: CGPoint(x: center.x - 10, y: center.y))
context.addLine(to: CGPoint(x: center.x - 80, y: center.y - 40))
context.strokePath()

// Draw '_'
context.move(to: CGPoint(x: center.x + 20, y: center.y - 40))
context.addLine(to: CGPoint(x: center.x + 80, y: center.y - 40))
context.strokePath()

// Draw dots (agents)
let dotColors = [NSColor.systemOrange, NSColor.systemGreen, NSColor.systemBlue]
let dotPositions = [
    CGPoint(x: center.x + 180, y: center.y + 250),
    CGPoint(x: center.x - 220, y: center.y + 120),
    CGPoint(x: center.x - 120, y: center.y - 280)
]

for (i, pos) in dotPositions.enumerated() {
    context.setFillColor(dotColors[i].cgColor)
    let dotRect = CGRect(x: pos.x - 20, y: pos.y - 20, width: 40, height: 40)
    context.fillEllipse(in: dotRect)
    
    // Add glow
    context.setStrokeColor(dotColors[i].withAlphaComponent(0.4).cgColor)
    context.setLineWidth(12)
    context.strokeEllipse(in: dotRect.insetBy(dx: -10, dy: -10))
}

image.unlockFocus()

// Save to file
if let tiffData = image.tiffRepresentation,
   let bitmapImage = NSBitmapImageRep(data: tiffData),
   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "icon.png"))
}
