import Foundation

/// Fetches Google's own autocomplete suggestions (the same undocumented
/// endpoint Firefox's address bar uses) — no API key required.
enum GoogleSuggestClient {
    static func fetchSuggestions(for query: String) async -> [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)")
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count > 1,
                  let suggestions = json[1] as? [String]
            else { return [] }
            return Array(suggestions.prefix(3))
        } catch {
            return []
        }
    }
}
