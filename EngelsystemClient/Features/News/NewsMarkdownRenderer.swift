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
/// re-injecting what `Text` won't: a "•"/"1." prefix for list items, indented two
/// spaces per nesting level (a tight single newline for anything inside a list,
/// regardless of depth changes — see below — a blank line between other blocks so
/// paragraphs stay visually separated), bold/larger text for headers, `.secondary`
/// color for block quotes. Inline emphasis (bold/italic/links/code) still renders
/// correctly on its own via `Text`, since those runs are copied through unchanged.
enum NewsMarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        render(markdown, parse: parseFullSyntax)
    }

    /// `parse` is the seam that lets the "markdown failed to parse" fallback be tested —
    /// `AttributedString(markdown:)` essentially never throws for real input.
    static func render(_ markdown: String, parse: (String) throws -> AttributedString) -> AttributedString {
        guard let parsed = try? parse(markdown) else {
            return AttributedString(markdown)
        }
        return reflowingBlocks(of: parsed)
    }

    private static func parseFullSyntax(_ markdown: String) throws -> AttributedString {
        try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full))
    }

    private static func reflowingBlocks(of input: AttributedString) -> AttributedString {
        var output = AttributedString()
        // Identifies which paragraph-level block a run belongs to, so consecutive runs
        // within the same block (e.g. plain text and a **bold** sub-run inside it)
        // don't each get their own newline/prefix — only the first run of a new block does.
        var lastParagraphIdentity: Int?

        for run in input.runs {
            let components = run.presentationIntent?.components ?? []
            let paragraphIdentity = components.first { isParagraph($0.kind) }?.identity
            // `components` is ordered innermost-to-outermost, so `.first` here is the
            // *immediately* enclosing list/item — the one that actually determines this
            // run's own bullet/number. Nesting depth is simply how many `.listItem`s are
            // in the chain (2026-09-22, user-reported: a first version only ever looked
            // at the single innermost list, so a nested list rendered with no
            // indentation and — since its own identity differed from the outer list's —
            // an incorrect blank-line gap instead of sitting right under its parent item).
            let listItemComponent = components.first { isListItem($0.kind) }
            let listComponent = components.first { isList($0.kind) }
            let nestingDepth = components.count { isListItem($0.kind) }
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
                // Any run that's part of a list — whichever depth, same or different
                // from the previous run's — stays tightly attached to the list rather
                // than getting a paragraph-style blank-line gap. Only entering/leaving
                // list context entirely (a plain paragraph, header, or block quote)
                // gets the wider break.
                let isListContext = listItemComponent != nil
                if !output.characters.isEmpty {
                    output += AttributedString(isListContext ? "\n" : "\n\n")
                }
                if let listItemComponent, let listComponent {
                    let indent = String(repeating: "  ", count: max(nestingDepth - 1, 0))
                    output += AttributedString(indent + listPrefix(item: listItemComponent.kind, list: listComponent.kind))
                }
                lastParagraphIdentity = paragraphIdentity
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
