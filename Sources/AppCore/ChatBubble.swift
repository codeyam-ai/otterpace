import SwiftUI

// A single chat bubble: user messages hug the trailing edge in a coral card;
// coach messages lead with a small Buddy and tint to the reply's mood, with an
// amber shield when the answer carries a safety flag.
struct ChatBubble: View {
    let message: ChatMessage

    /// Turn bare `host/path` URLs in coach copy into tappable links.
    ///
    /// Coach prose is plain text (the model returns a string, and app-authored
    /// error copy is a literal), so a billing link would otherwise render as
    /// something the user has to retype. `.inlineOnlyPreservingWhitespace`
    /// keeps the prose intact and only lifts the links.
    static func linkified(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let pattern = #"(?:https?://)?(?:platform\.openai\.com|console\.anthropic\.com|aistudio\.google\.com)/[^\s,)]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Apply back-to-front so earlier ranges stay valid as we edit.
        for match in matches.reversed() {
            let raw = ns.substring(with: match.range)
            let absolute = raw.hasPrefix("http") ? raw : "https://\(raw)"
            guard let url = URL(string: absolute),
                  let range = out.range(of: raw) else { continue }
            out[range].link = url
            out[range].underlineStyle = .single
        }
        return out
    }

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(Typography.body)
                    .foregroundColor(Palette.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        case .coach:
            HStack(alignment: .top, spacing: 8) {
                BuddyView(mood: message.mood, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    if message.safetyFlag {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(Palette.amber)
                            Text("SAFETY FIRST")
                                .font(Typography.caption2)
                                .foregroundColor(Palette.amber)
                        }
                    }
                    // Rendered through AttributedString's inline-markdown parser
                    // so a bare URL in the copy (e.g. the "add credits" billing
                    // link) becomes tappable instead of text the user has to
                    // retype into a browser. Falls back to the plain string when
                    // the text is not parseable, so no message can be lost here.
                    Text(ChatBubble.linkified(message.text))
                        .font(Typography.body)
                        .foregroundColor(Palette.ink)
                        .tint(Palette.brand)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.safetyFlag
                              ? Palette.amber.opacity(0.12)
                              : message.mood.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke((message.safetyFlag ? Palette.amber : message.mood.accent).opacity(0.25), lineWidth: 1)
                )
                Spacer(minLength: 24)
            }
        }
    }
}
