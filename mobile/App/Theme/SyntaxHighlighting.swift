// SyntaxHighlighting — renders SyntaxHighlighter tokens into an AttributedString.
// UI-layer only: color choices live here so HyperGitCore stays SwiftUI-free and
// its tokenizer stays independently testable (see SyntaxHighlighterTests).
import SwiftUI
import HyperGitCore

enum SyntaxHighlighting {
    static func attributedString(for text: String, language: SyntaxLanguage) -> AttributedString {
        var attributed = AttributedString(text)
        guard language != .plain else { return attributed }
        for token in SyntaxHighlighter.tokens(in: text, language: language) {
            apply(token, to: &attributed, source: text)
        }
        return attributed
    }

    private static func apply(_ token: SyntaxToken, to attributed: inout AttributedString, source: String) {
        guard let stringRange = Range(token.range, in: source),
              let start = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let end = AttributedString.Index(stringRange.upperBound, within: attributed) else { return }
        attributed[start..<end].foregroundColor = color(for: token.kind)
    }

    private static func color(for kind: SyntaxToken.Kind) -> Color {
        switch kind {
        case .keyword: return .purple
        case .string: return .red
        case .comment: return .secondary
        case .number: return .blue
        }
    }
}
