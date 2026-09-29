import Foundation
import CoreGraphics
import ImageIO

// Wrap the existing app icon in a 96-point, rounded PDF for use by both
// the static Launch Screen and SwiftUI. The original artwork stays intact.
guard CommandLine.arguments.count == 3 else {
    throw NSError(domain: "LaunchIconExport", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Pass the source AppIcon.png and output LaunchIcon.pdf paths."])
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let icon = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    throw NSError(domain: "LaunchIconExport", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Cannot read the source app icon."])
}
var bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
guard let context = CGContext(destination as CFURL, mediaBox: &bounds, nil) else {
    throw NSError(domain: "LaunchIconExport", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Cannot create the launch icon PDF."])
}
context.beginPDFPage(nil)
context.addPath(CGPath(roundedRect: bounds, cornerWidth: 22, cornerHeight: 22, transform: nil))
context.clip()
context.draw(icon, in: bounds)
context.endPDFPage()
context.closePDF()
