import SwiftUI
import AppCore
#if canImport(AppKit)
import AppKit
#endif

// Rasterizes `AppIconArtwork` to the App Store marketing icon:
// App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png — exactly 1024×1024,
// sRGB, OPAQUE (no alpha channel; the artwork is flattened onto the coral
// background). Re-run whenever the mascot art changes:  swift run GenerateAppIcon
//
// Reuses the in-app `AppIconArtwork` SwiftUI view so the icon stays pixel-
// consistent with the mascot instead of a hand-painted PNG that drifts.

@main
struct GenerateAppIcon {
    static func main() {
        let outPath = "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
        let side = 1024

        guard #available(macOS 13.0, *) else {
            fputs("error: GenerateAppIcon needs macOS 13+ (ImageRenderer)\n", stderr)
            exit(1)
        }
        #if canImport(AppKit)
        let renderer = ImageRenderer(content: AppIconArtwork(mood: .ready, canvas: CGFloat(side)))
        renderer.scale = 1  // canvas is already 1024pt → 1024px
        guard let rendered = renderer.cgImage else {
            fputs("error: ImageRenderer produced no image\n", stderr); exit(1)
        }

        // Flatten onto an OPAQUE RGB context (noneSkipLast => no alpha channel),
        // pre-filling the brand coral so any edge transparency reads as coral.
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            fputs("error: could not create bitmap context\n", stderr); exit(1)
        }
        ctx.setFillColor(CGColor(red: 1.0, green: 0.45, blue: 0.34, alpha: 1))  // Palette.brand
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let flattened = ctx.makeImage() else {
            fputs("error: could not flatten image\n", stderr); exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: flattened)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("error: PNG encode failed\n", stderr); exit(1)
        }
        do {
            try FileManager.default.createDirectory(
                atPath: (outPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: outPath))
            print("wrote \(outPath) (\(side)x\(side), opaque)")
        } catch {
            fputs("error: write failed: \(error)\n", stderr); exit(1)
        }
        #else
        fputs("error: GenerateAppIcon requires AppKit (macOS)\n", stderr)
        exit(1)
        #endif
    }
}
