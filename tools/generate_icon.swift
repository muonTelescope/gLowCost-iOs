// Render the existing MuonGlyph for the Home Screen. Run from repository root.
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red:18/255,green:14/255,blue:26/255,alpha:1))
context.fill(CGRect(x:0,y:0,width:1024,height:1024))
context.setStrokeColor(CGColor(red:201/255,green:182/255,blue:255/255,alpha:1))
let p = CGMutablePath()
func point(_ x:Double,_ y:Double)->CGPoint { CGPoint(x:272+480*x,y:212+600*(1-y)) }
for (a,b,c,d) in [(0.22,0.0,0.40,1.0),(0.52,0.0,0.78,1.0),(0.08,0.52,0.92,0.52)] {
p.move(to:point(a,b)); p.addLine(to:point(c,d))
}
context.setLineWidth(600/9)
context.setLineCap(.square)
context.addPath(p)
context.strokePath()
let url = URL(fileURLWithPath:"MuonMonitor/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
