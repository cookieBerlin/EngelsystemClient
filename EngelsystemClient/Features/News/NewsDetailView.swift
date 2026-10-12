import SwiftUI
import EngelsystemClientKit

/// Pushed from a News row's "N Comments" link (added 2026-09-22). Shows the post's
/// full text plus its comments, fetched live (see `NewsDetailViewModel`) rather than
/// cached — this screen is only ever reached to read comments, so there's nothing
/// to keep around once it's dismissed.
struct NewsDetailView: View {
    let item: CachedNews
    let instance: Instance

    @State private var viewModel = NewsDetailViewModel()

    private var textParts: CachedNews.TextParts { CachedNews.textParts(from: item.text) }

    private func attributed(_ text: String) -> AttributedString {
        NewsMarkdownRenderer.render(text)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(attributed(textParts.preview))
                        .font(.body)
                    if let rest = textParts.rest {
                        Text(attributed(rest))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            // COMPAT(#1710): hidden when the server has no news comments.
            if !viewModel.commentsUnavailable {
            Section("Comments") {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                        .listRowInsets(EdgeInsets())
                } else if viewModel.comments.isEmpty {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.comments) { comment in
                        NewsCommentRow(comment: comment)
                    }
                }
            }
            }
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.refresh(newsServerID: item.serverID, instance: instance) }
    }
}

private struct NewsCommentRow: View {
    let comment: NewsComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // `Reference.name` is documented as optional ("should only be used
                // for reference") — fall back rather than showing a blank author.
                Text(comment.user.name ?? "Unknown")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(comment.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
