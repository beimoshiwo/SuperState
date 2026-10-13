import AppKit

// DMG 窗口背景图生成器：
// 左侧 App 图标 + 箭头 + 右侧应用程序文件夹图标 + "拖动安装" 提示文字
// 用法: make_dmg_bg <appIcon.png> <out.png>

let args = CommandLine.arguments
guard args.count >= 3,
      let appIcon = NSImage(contentsOfFile: args[1]) else {
    print("usage: make_dmg_bg <appIcon.png> <out.png>")
    exit(1)
}

let W: CGFloat = 660, H: CGFloat = 420
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// 背景：浅灰白
NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let iconSize: CGFloat = 128
let iconY = H / 2 - iconSize / 2 + 30

// 左：App 图标
appIcon.draw(in: NSRect(x: 110, y: iconY, width: iconSize, height: iconSize),
             from: .zero, operation: .sourceOver, fraction: 1)

// 右：应用程序文件夹图标
let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
folderIcon.size = NSSize(width: iconSize, height: iconSize)
folderIcon.draw(in: NSRect(x: W - 110 - iconSize, y: iconY, width: iconSize, height: iconSize),
                from: .zero, operation: .sourceOver, fraction: 1)

// 中间箭头
let arrow = NSBezierPath()
let ay = iconY + iconSize / 2
let ax0: CGFloat = 110 + iconSize + 36
let ax1: CGFloat = W - 110 - iconSize - 36
arrow.move(to: NSPoint(x: ax0, y: ay))
arrow.line(to: NSPoint(x: ax1 - 14, y: ay))
arrow.move(to: NSPoint(x: ax1 - 26, y: ay + 12))
arrow.line(to: NSPoint(x: ax1 - 8, y: ay))
arrow.line(to: NSPoint(x: ax1 - 26, y: ay - 12))
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

// 文字
func drawText(_ s: String, centerX: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, color: NSColor) {
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let w = str.size().width
    str.draw(at: NSPoint(x: centerX - w / 2, y: y))
}

drawText("将 SuperState 拖动到「应用程序」文件夹完成安装",
         centerX: W / 2, y: iconY + iconSize + 20, size: 18, bold: true, color: NSColor(calibratedWhite: 0.25, alpha: 1))
drawText("SuperState", centerX: 110 + iconSize / 2, y: iconY - 24, size: 13, bold: false,
         color: NSColor(calibratedWhite: 0.35, alpha: 1))
drawText("应用程序", centerX: W - 110 - iconSize / 2, y: iconY - 24, size: 13, bold: false,
         color: NSColor(calibratedWhite: 0.35, alpha: 1))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("render failed")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: args[2]))
print("background: \(args[2])")
