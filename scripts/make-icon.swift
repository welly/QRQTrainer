// Renders the QRQ Trainer app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift            (from the repository root)
//        swift scripts/make-icon.swift preview.png (also writes a 1024 px PNG)
import AppKit
import SwiftUI

struct AppIcon: View {
    // Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
    private let size: CGFloat = 824
    private let corner: CGFloat = 185

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 0.98),
                                              Color(red: 0.06, green: 0.20, blue: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)

            MorseQ()
        }
        .frame(width: 1024, height: 1024)
    }
}

/// "Q" in Morse: dah dah dit dah. QRQ means "send faster".
struct MorseQ: View {
    private let height: CGFloat = 76
    private let dah: CGFloat = 152
    private let gap: CGFloat = 36

    var body: some View {
        HStack(spacing: gap) {
            element(dah); element(dah); element(height); element(dah)
        }
    }

    private func element(_ width: CGFloat) -> some View {
        Capsule().fill(.white).frame(width: width, height: height)
    }
}

@MainActor
func renderPNG(size: Int) -> Data {
    let renderer = ImageRenderer(content: AppIcon().scaleEffect(CGFloat(size) / 1024).frame(width: CGFloat(size), height: CGFloat(size)))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
func main() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: iconset) }

    for base in [16, 32, 128, 256, 512] {
        try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }

    let resources = root.appendingPathComponent("Resources")
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    let output = resources.appendingPathComponent("AppIcon.icns")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("Wrote \(output.path)")

    if CommandLine.arguments.count > 1 {
        let preview = URL(fileURLWithPath: CommandLine.arguments[1])
        try renderPNG(size: 1024).write(to: preview)
        print("Wrote \(preview.path)")
    }
}

try MainActor.assumeIsolated { try main() }
