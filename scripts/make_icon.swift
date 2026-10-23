import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.035, green: 0.12, blue: 0.18, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(calibratedRed: 0.17, green: 0.78, blue: 0.67, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 125, y: 175, width: 774, height: 674), xRadius: 115, yRadius: 115).fill()
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font:NSFont.monospacedSystemFont(ofSize: 365, weight: .bold), .foregroundColor:NSColor(calibratedRed: 0.035, green: 0.12, blue: 0.18, alpha: 1), .paragraphStyle:paragraph]
("Py" as NSString).draw(in: NSRect(x: 100, y: 290, width: 824, height: 450), withAttributes: attrs)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
