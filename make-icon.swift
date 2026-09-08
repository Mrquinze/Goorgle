// Generates Goorgle/Goorgle.icns (and a 1024px PNG for docs) from code, so the
// app icon is reproducible rather than a binary someone has to redraw.
//
// Build and run it against the app's own G mark, so the icon and the in-app
// glyph can never drift apart:
//
//   cd Goorgle
//   swiftc -o /tmp/make-icon ../scripts/make-icon.swift Views/GoogleGMark.swift
//   /tmp/make-icon .            # writes ./Goorgle.icns and ./Goorgle-icon.png
//
// The concept: the four-color G *is* the lens of a magnifying glass. It reads
// as "search" at a glance and as the Google parody the app is named for, and —
// unlike a picture of the search pill — it survives being shrunk to 16px.

import AppKit
import SwiftUI

struct AppIconArt: View {
    var body: some View {
        GeometryReader { geo in
            // macOS icons occupy ~80% of their canvas as a continuous rounded
            // square, so this lines up with every other icon in the Dock.
            let canvas = geo.size.width
            let side = canvas * 0.805
            let radius = side * 0.225

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 1.0), Color(white: 0.90)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: side * 0.006)
                    )
                    .shadow(color: .black.opacity(0.20), radius: side * 0.028, y: side * 0.016)
                    .frame(width: side, height: side)

                ZStack {
                    // Handle first, so the lens sits on top of where they meet
                    // and the join needs no masking.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.32), Color(white: 0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        // Sized and placed so the inner tip ends *under* the
                        // ring's stroke band rather than inside the lens,
                        // where it read as a stray dark blob.
                        .frame(width: side * 0.105, height: side * 0.30)
                        .rotationEffect(.degrees(-45))
                        .offset(x: side * 0.235, y: side * 0.235)

                    GoogleGMark()
                        .frame(width: side * 0.60, height: side * 0.60)
                        .offset(x: -side * 0.035, y: -side * 0.035)
                }
                .frame(width: side, height: side)
            }
            .frame(width: canvas, height: canvas)
        }
    }
}

@MainActor
func png(at pixels: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: AppIconArt().frame(width: pixels, height: pixels))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    // ImageRenderer hands back a representation sized in points; restate it in
    // pixels so the .icns entries are exactly the sizes iconutil expects.
    bitmap.size = NSSize(width: pixels, height: pixels)
    return bitmap.representation(using: .png, properties: [:])
}

@MainActor
func generate(into directory: URL) {
    let iconset = directory.appendingPathComponent("Goorgle.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let entries: [(name: String, pixels: CGFloat)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    for entry in entries {
        guard let data = png(at: entry.pixels) else {
            print("failed rendering \(entry.name)"); exit(1)
        }
        try? data.write(to: iconset.appendingPathComponent(entry.name))
    }

    if let large = png(at: 1024) {
        try? large.write(to: directory.appendingPathComponent("Goorgle-icon.png"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path,
                         "-o", directory.appendingPathComponent("Goorgle.icns").path]
    try? process.run()
    process.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)

    print(process.terminationStatus == 0
          ? "wrote Goorgle.icns + Goorgle-icon.png in \(directory.path)"
          : "iconutil failed (\(process.terminationStatus))")
    exit(process.terminationStatus)
}

// `@main` rather than top-level code: Swift only allows the latter in a file
// literally named main.swift, and this one is compiled alongside the app's
// GoogleGMark.swift.
@main
struct MakeIcon {
    static func main() {
        let target = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        Task { @MainActor in generate(into: target) }
        RunLoop.main.run()
    }
}
