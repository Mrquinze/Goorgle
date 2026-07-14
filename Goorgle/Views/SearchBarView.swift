import SwiftUI
import AppKit

/// Android 16 (Material 3 expressive) style search bar: a large, fully
/// rounded pill with a leading search glyph and a trailing Google mark,
/// over a sky blue gradient instead of the stock white/gray fill.
/// Up to 3 live suggestions expand below the pill as a matching rounded
/// list. The panel behind this view is transparent and fixed-size, so
/// the unused space when there are no suggestions is simply invisible.
struct SearchBarView: View {
    var onDismiss: () -> Void

    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var highlightedIndex: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pill

            if !suggestions.isEmpty {
                suggestionsList
            }
        }
        .padding(16)
        .frame(width: 360, height: 230, alignment: .top)
        .onAppear { isFocused = true }
        .onExitCommand { onDismiss() }
        .onMoveCommand(perform: handleMoveCommand)
        .task(id: query) { await loadSuggestions() }
    }

    private var pill: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.9))
                .font(.system(size: 16, weight: .medium))

            TextField("Search Google or type a URL", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isFocused)
                .onSubmit(performSearch)

            GoogleGMark()
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Capsule().fill(pillGradient))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    search(for: suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(suggestion)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(index == highlightedIndex ? Color.white.opacity(0.18) : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(pillGradient.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private var pillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.42, green: 0.73, blue: 0.98),
                Color(red: 0.18, green: 0.51, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !suggestions.isEmpty else { return }
        switch direction {
        case .down:
            let next = (highlightedIndex ?? -1) + 1
            highlightedIndex = min(next, suggestions.count - 1)
        case .up:
            let previous = (highlightedIndex ?? 0) - 1
            highlightedIndex = previous < 0 ? nil : previous
        default:
            break
        }
    }

    private func loadSuggestions() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            suggestions = []
            highlightedIndex = nil
            return
        }
        // Debounce: SwiftUI's .task(id:) cancels this automatically when
        // `query` changes again before the sleep finishes.
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        let results = await GoogleSuggestClient.fetchSuggestions(for: query)
        if !Task.isCancelled {
            suggestions = results
            highlightedIndex = nil
        }
    }

    private func performSearch() {
        if let highlightedIndex, suggestions.indices.contains(highlightedIndex) {
            search(for: suggestions[highlightedIndex])
        } else {
            search(for: query)
        }
    }

    private func search(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let looksLikeURL = trimmed.contains(".") && !trimmed.contains(" ")
        let urlString: String
        if looksLikeURL {
            urlString = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = "https://www.google.com/search?q=\(encoded)"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        query = ""
        suggestions = []
        onDismiss()
    }
}

#Preview {
    SearchBarView(onDismiss: {})
}
