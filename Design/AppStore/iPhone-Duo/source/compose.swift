import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/AppStore/iPhone-Duo", isDirectory: true)
let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let width = 2853, height = 2007
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: 1)
}
let background = color(0xF3F1EC), ink = color(0x1E2B32), accent = color(0x007E73), secondary = color(0x4D565C)
struct Copy {
    let key: String, first: String, second: String, subtitle: String
}
let chinese = [
    Copy(key:"01-terminal", first:"终端在手", second:"随时掌控", subtitle:"多标签终端，大屏操作更从容"),
    Copy(key:"02-hosts", first:"所有主机", second:"井然有序", subtitle:"分组管理，最近连接快速返回"),
    Copy(key:"03-files", first:"远程文件", second:"轻松打理", subtitle:"终端与 SFTP 文件，同屏协作"),
    Copy(key:"04-sync", first:"全平台可用", second:"安全同步", subtitle:"macOS · Windows · Linux · iOS · 安卓"),
]
let english = [
    Copy(key:"01-terminal", first:"Your terminal", second:"Anywhere", subtitle:"Terminal tabs, with room to work."),
    Copy(key:"02-hosts", first:"Every host", second:"Organized", subtitle:"Groups and recent connections, all in one place."),
    Copy(key:"03-files", first:"Remote files", second:"Made simple", subtitle:"Your terminal and SFTP files, side by side."),
    Copy(key:"04-sync", first:"Every platform", second:"Secure sync", subtitle:"macOS · Windows · Linux · iOS · Android"),
]
func font(_ name: String, _ size: CGFloat) -> NSFont {
    guard let font = NSFont(name:name,size:size) else { fatalError("Missing native font: \(name)") }
    return font
}
func textWidth(_ text: String, font: NSFont) -> CGFloat {
    (text as NSString).size(withAttributes:[.font:font]).width
}
func text(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
    (text as NSString).draw(at:point,withAttributes:[.font:font,.foregroundColor:color])
}
func context(_ width:Int,_ height:Int) -> CGContext {
    let space = CGColorSpace(name:CGColorSpace.sRGB)!
    let ctx = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                        space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    ctx.translateBy(x:0,y:CGFloat(height));ctx.scaleBy(x:1,y:-1)
    ctx.interpolationQuality = .high
    return ctx
}
func write(_ ctx: CGContext, to url: URL) throws {
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(destination,image,nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}
for (language,copies) in [("zh-Hans",chinese),("en",english)] {
    for copy in copies {
        let ctx=context(width,height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
        background.setFill();NSRect(x:0,y:0,width:width,height:height).fill()
        let icon=NSImage(contentsOf:project.appending(path:"ShellRS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))!
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect:NSRect(x:252,y:72,width:112,height:112),xRadius:25,yRadius:25).addClip()
        icon.draw(in:NSRect(x:252,y:72,width:112,height:112),from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        text("ShellRS",at:CGPoint(x:404,y:80),font:font("HelveticaNeue-Medium",94),color:ink)
        let titleFontName=language=="zh-Hans" ? "PingFangSC-Semibold" : "HelveticaNeue-Bold"
        var titleSize:CGFloat=language=="zh-Hans" ? 104 : 94
        while textWidth(copy.first,font:font(titleFontName,titleSize))+44+textWidth(copy.second,font:font(titleFontName,titleSize)) > 1520 { titleSize-=1 }
        let titleFont=font(titleFontName,titleSize)
        text(copy.first,at:CGPoint(x:1080,y:66),font:titleFont,color:ink)
        let secondX=1080+textWidth(copy.first,font:titleFont)+44
        text(copy.second,at:CGPoint(x:secondX,y:66),font:titleFont,color:accent)
        let subName=language=="zh-Hans" ? "PingFangSC-Medium" : "HelveticaNeue-Medium"
        var subSize:CGFloat=40
        while textWidth(copy.subtitle,font:font(subName,subSize))>1520 {subSize-=1}
        text(copy.subtitle,at:CGPoint(x:1080,y:190),font:font(subName,subSize),color:secondary)
        let screenWidth:CGFloat=2305
        let screenHeight=screenWidth*CGFloat(height)/CGFloat(width)
        let screen=NSRect(x:274,y:302,width:screenWidth,height:screenHeight)
        let frame=screen.insetBy(dx:-22,dy:-22)
        color(0x151719).setFill()
        NSBezierPath(roundedRect:frame,xRadius:104,yRadius:104).fill()
        let input=root.appending(path:"raw/\(language)/\(copy.key).png")
        guard let screenshot=NSImage(contentsOf:input) else {fatalError("Missing screenshot \(input.path)")}
        let rep=screenshot.representations.first!
        guard rep.pixelsWide==width,rep.pixelsHigh==height else {fatalError("Wrong source geometry")}
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect:screen,xRadius:82,yRadius:82).addClip()
        screenshot.draw(in:screen,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        let output=root.appending(path:"\(language)/\(copy.key).png")
        try write(ctx,to:output)
        print("Rendered \(output.path) (headline \(Int(titleSize))pt)")
    }
}
// A compact review sheet; upload the individual files above, not this overview.
let previewWidth=1600, cellWidth:CGFloat=760, cellHeight:CGFloat=535
let previewHeight=4*590+48
let ctx=context(previewWidth,previewHeight)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
background.setFill();NSRect(x:0,y:0,width:previewWidth,height:previewHeight).fill()
for (column,language) in ["zh-Hans","en"].enumerated() {
    for (row,key) in ["01-terminal","02-hosts","03-files","04-sync"].enumerated() {
        let x=CGFloat(28+column*784),y=CGFloat(28+row*590)
        text("\(language) / \(key)",at:CGPoint(x:x,y:y),font:font("HelveticaNeue-Medium",20),color:ink)
        let image=NSImage(contentsOf:root.appending(path:"\(language)/\(key).png"))!
        image.draw(in:NSRect(x:x,y:y+32,width:cellWidth,height:cellHeight),from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
    }
}
NSGraphicsContext.restoreGraphicsState()
try write(ctx,to:root.appending(path:"overview.png"))
