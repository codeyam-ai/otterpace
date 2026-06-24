import SwiftUI
import AppCore
#if canImport(AppKit)
import AppKit
#endif

// Generates Otterpace's brand image assets from the in-app SwiftUI views, so they
// stay pixel-consistent with the mascot instead of hand-painted PNGs that drift.
// Re-run whenever the mascot art changes:  swift run GenerateAppIcon
//
//   1. App icon  -> App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//      1024×1024, sRGB, OPAQUE (no alpha; AppIconArtwork flattened onto coral).
//   2. Launch image (Buddy, transparent) -> App/Assets.xcassets/LaunchBuddy.imageset
//      at 1x/2x/3x, used by the Info.plist UILaunchScreen over the coral
//      LaunchBackground color.

// The transparent launch mark: Buddy centered in a square with clear margins, so
// it sits cleanly on the coral launch background.
private struct LaunchBuddyMark: View {
    let px: CGFloat
    var body: some View {
        PuffyBuddy(mood: .ready, size: px * 0.6, showHalo: false)
            .frame(width: px, height: px)
    }
}

@main
struct GenerateAppIcon {
    @MainActor
    static func main() {
        guard #available(macOS 13.0, *) else {
            fputs("error: GenerateAppIcon needs macOS 13+ (ImageRenderer)\n", stderr)
            exit(1)
        }
        #if canImport(AppKit)
        // 1) App icon — opaque 1024, flattened onto coral.
        writeOpaque(
            view: AppIconArtwork(mood: .ready, canvas: 1024),
            px: 1024,
            to: "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

        // 2) Launch image — transparent Buddy at 1x/2x/3x (~200pt mark).
        for (scale, name) in [(1, "LaunchBuddy.png"), (2, "LaunchBuddy@2x.png"), (3, "LaunchBuddy@3x.png")] {
            let px = 200 * scale
            writeTransparent(
                view: LaunchBuddyMark(px: CGFloat(px)),
                px: px,
                to: "App/Assets.xcassets/LaunchBuddy.imageset/\(name)")
        }
        #else
        fputs("error: GenerateAppIcon requires AppKit (macOS)\n", stderr)
        exit(1)
        #endif
    }

    #if canImport(AppKit)
    @MainActor @available(macOS 13.0, *)
    private static func render<V: View>(_ view: V, px: Int) -> CGImage? {
        let r = ImageRenderer(content: view)
        r.scale = 1  // views are authored at the target pixel size already
        return r.cgImage
    }

    // Opaque output: flatten onto the brand coral so the PNG has no alpha channel.
    @MainActor @available(macOS 13.0, *)
    private static func writeOpaque<V: View>(view: V, px: Int, to path: String) {
        guard let rendered = render(view, px: px) else { fail("render", path) }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("context", path) }
        ctx.setFillColor(CGColor(red: 1.0, green: 0.45, blue: 0.34, alpha: 1))  // Palette.brand
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: px, height: px))
        guard let flat = ctx.makeImage() else { fail("flatten", path) }
        writePNG(flat, to: path, note: "\(px)x\(px), opaque")
    }

    // Transparent output: keep the alpha channel (Buddy on clear).
    @MainActor @available(macOS 13.0, *)
    private static func writeTransparent<V: View>(view: V, px: Int, to path: String) {
        guard let rendered = render(view, px: px) else { fail("render", path) }
        writePNG(rendered, to: path, note: "\(px)x\(px), transparent")
    }

    private static func writePNG(_ image: CGImage, to path: String, note: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("encode", path) }
        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(note))")
        } catch { fail("write: \(error)", path) }
    }

    private static func fail(_ what: String, _ path: String) -> Never {
        fputs("error: \(what) failed for \(path)\n", stderr); exit(1)
    }
    #endif
}
