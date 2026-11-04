// Renders the QRQ Trainer app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift            (from the repository root)
//        swift scripts/make-icon.swift preview.png (also writes a 1024 px PNG)
import AppKit
import SwiftUI

struct AppIcon: View {
    // Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
    private let body824: CGFloat = 824
    private let corner: CGFloat = 185

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.45, blue: 1.00),
                                              Color(red: 0.07, green: 0.13, blue: 0.45)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    // Soft sheen across the top half.
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 3)
                )
                .frame(width: body824, height: body824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)

            RadioWaves()
                .frame(width: body824, height: body824)

            VStack(spacing: 70) {
                MorseQ()
                SpeedSwoosh()
            }
            .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// "Q" in Morse: dah dah dit dah, with motion streaks trailing each element.
struct MorseQ: View {
    private let height: CGFloat = 62
    private let dah: CGFloat = 156
    private let dit: CGFloat = 62
    private let gap: CGFloat = 36

    var body: some View {
        HStack(spacing: gap) {
            element(dah); element(dah); element(dit); element(dah)
        }
    }

    private func element(_ width: CGFloat) -> some View {
        Capsule()
            .fill(.white)
            .frame(width: width, height: height)
            .shadow(color: Color(red: 0.55, green: 0.80, blue: 1).opacity(0.9), radius: 22)
    }
}

/// Tapering streak under the code: faint on the left, bright on the right, for speed.
struct SpeedSwoosh: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 22) {
            streak(width: 560, height: 14, opacity: 0.85)
            streak(width: 400, height: 10, opacity: 0.55)
            streak(width: 250, height: 8, opacity: 0.35)
        }
        .frame(width: 600, alignment: .trailing)
    }

    private func streak(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(opacity)], startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: height)
    }
}

/// Faint radio-wave arcs radiating from the top-right corner.
struct RadioWaves: View {
    var body: some View {
        Canvas { ctx, size in
            let centre = CGPoint(x: size.width * 0.81, y: size.height * 0.17)
            for (i, radius) in [62.0, 118.0, 174.0].enumerated() {
                var arc = Path()
                arc.addArc(center: centre, radius: radius, startAngle: .degrees(100), endAngle: .degrees(170), clockwise: false)
                ctx.stroke(arc, with: .color(.white.opacity(0.30 - Double(i) * 0.07)),
                           style: StrokeStyle(lineWidth: 16, lineCap: .round))
            }
            let dot = Path(ellipseIn: CGRect(x: centre.x - 16, y: centre.y - 16, width: 32, height: 32))
            ctx.fill(dot, with: .color(.white.opacity(0.4)))
        }
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
