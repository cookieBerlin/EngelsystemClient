import SwiftUI

/// Renders block-level markdown (lists, headers, block quotes) for `Text`, which
/// `AttributedString(markdown:)` alone can't do (2026-09-22, user-reported: switching
/// its `interpretedSyntax` to `.full` correctly *parses* block structure into
/// `PresentationIntent`s, but `Text` silently ignores those — it only renders inline
/// attributes like bold/italic/links. Under `.full`, list/header markers are consumed
/// as structure with nothing left to show for it, so lists disappeared entirely
/// rather than at least showing as a literal "-"/"*" like before this was attempted).
///
/// Works around this by walking the parsed `AttributedString`'s runs and manually
/// re-injecting what `Text` won't: a "•"/"1." prefix for list items (tight single
/// newline between items in the same list, a blank line between other blocks so
/// paragraphs stay visually separated) and bold/larger text for headers, `.secondary`
/// color for block quotes. Inline emphasis (bold/italic/links/code) still renders
/// correctly on its own via `Text`, since those runs are copied through unchanged.
enum NewsMarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return AttributedString(markdown)
        }
        return reflowingBlocks(of: parsed)
    }

    private static func reflowingBlocks(of input: AttributedString) -> AttributedString {
        var output = AttributedString()
        // Identifies which paragraph-level block a run belongs to, so consecutive runs
        // within the same block (e.g. plain text and a **bold** sub-run inside it)
        // don't each get their own newline/prefix — only the first run of a new block does.
        var lastParagraphIdentity: Int?
        // Tracks the enclosing list's identity so consecutive items in the *same* list
        // get a tight single-newline separator, while switching to/from a different
        // block type still gets a full blank-line paragraph break.
        var lastListIdentity: Int?

        for run in input.runs {
            let components = run.presentationIntent?.components ?? []
            let paragraphIdentity = components.first { isParagraph($0.kind) }?.identity
            let listItemComponent = components.first { isListItem($0.kind) }
            let listComponent = components.first { isList($0.kind) }
            let headerLevel = components.compactMap { headerLevel(of: $0.kind) }.first
            let isBlockQuote = components.contains { isBlockQuote($0.kind) }

            var runAttributed = AttributedString(input[run.range])
            if let headerLevel {
                runAttributed.font = .system(size: max(24 - CGFloat(headerLevel) * 2, 16), weight: .bold)
            }
            if isBlockQuote {
                runAttributed.foregroundColor = .secondary
            }

            if paragraphIdentity != lastParagraphIdentity {
                let continuesSameList = listComponent != nil && listComponent?.identity == lastListIdentity
                if !output.characters.isEmpty {
                    output += AttributedString(continuesSameList ? "\n" : "\n\n")
                }
                if let listItemComponent, let listComponent {
                    output += AttributedString(listPrefix(item: listItemComponent.kind, list: listComponent.kind))
                }
                lastParagraphIdentity = paragraphIdentity
                lastListIdentity = listComponent?.identity
            }

            output += runAttributed
        }
        return output
    }

    private static func isParagraph(_ kind: PresentationIntent.Kind) -> Bool {
        if case .paragraph = kind { return true }
        return false
    }

    private static func isListItem(_ kind: PresentationIntent.Kind) -> Bool {
        if case .listItem = kind { return true }
        return false
    }

    private static func isList(_ kind: PresentationIntent.Kind) -> Bool {
        switch kind {
        case .orderedList, .unorderedList: return true
        default: return false
        }
    }

    private static func headerLevel(of kind: PresentationIntent.Kind) -> Int? {
        if case let .header(level) = kind { return level }
        return nil
    }

    private static func isBlockQuote(_ kind: PresentationIntent.Kind) -> Bool {
        if case .blockQuote = kind { return true }
        return false
    }

    private static func listPrefix(item: PresentationIntent.Kind, list: PresentationIntent.Kind) -> String {
        let ordinal: Int
        if case let .listItem(value) = item { ordinal = value } else { ordinal = 1 }
        if case .orderedList = list {
            return "\(ordinal). "
        }
        return "\u{2022} "
    }
}
