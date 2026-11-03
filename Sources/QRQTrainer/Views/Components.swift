import AppKit
import QRQCore
import SwiftUI

/// Rounded container used throughout the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Keyboard shortcut hint, e.g. `KeyHint("F6")`.
struct KeyHint: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.caption.monospaced().weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.secondary)
    }
}

enum Diff {
    /// What the user typed, with mistakes coloured: wrong = red, extra = faded red, missing = orange underscore.
    static func received(_ result: CallResult) -> Text {
        if result.received.isEmpty { return Text(verbatim: "—").foregroundColor(.secondary) }
        var text = Text(verbatim: "")
        for item in Scoring.align(sent: result.sent, received: result.received) {
            switch item {
            case .match(let c):
                text = text + Text(verbatim: String(c))
            case .substitution(_, let c):
                text = text + Text(verbatim: String(c)).foregroundColor(.red)
            case .extra(let c):
                text = text + Text(verbatim: String(c)).foregroundColor(Color.red.opacity(0.55))
            case .missing:
                text = text + Text(verbatim: "_").foregroundColor(.orange)
            }
        }
        return text
    }
}

/// Lets a view react to keys a text field would otherwise swallow (F6 = repeat, as in classic trainers).
@MainActor
final class KeyMonitor {
    private var token: Any?

    func install(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        remove()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { handler(event) }
            return handled ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

enum ResponseFormat {
    /// "0.74 s", or "—" when the time wasn't measured.
    static func string(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        return (Double(ms) / 1000).formatted(.number.precision(.fractionLength(2))) + " s"
    }
}

extension Date {
    var shortDateTime: String { formatted(date: .abbreviated, time: .shortened) }
}
