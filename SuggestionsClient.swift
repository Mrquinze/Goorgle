import Foundation

/// Percent-encoding for text going into a URL *query value*, shared by the
/// suggest endpoints, the search URLs and the engine templates.
///
/// `.urlQueryAllowed` is the wrong set here: it permits `&`, `=`, `+` and `?`,
/// which are exactly the characters that break a value. Searching for
/// "salt & pepper" truncated the query at the ampersand, and "1+1" reached
/// Google as "1 1". Encoding everything outside RFC 3986's unreserved set
/// leaves no character able to escape the value it belongs to.
enum QueryEncoding {
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func percentEncoded(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}

/// Live autocomplete from whichever engine is selected.
///
/// Every engine Goorgle ships with replies in the OpenSearch suggestions
/// shape — `["typed", ["first", "second", …]]` — which was verified against
/// Google, DuckDuckGo, Brave, Bing and Ecosia, all of them without an API key
/// and without needing a browser User-Agent. So one parser covers the lot, and
/// a custom engine gets suggestions too the moment its suggest URL speaks the
/// same format. Startpage has no such endpoint: `suggestTemplate` is nil there
/// and the pill simply shows no suggestion rows.
enum SuggestionsClient {
    static func fetch(for query: String, from engine: SearchEngine, limit: Int = 5) async -> [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let template = engine.suggestTemplate,
              let url = SearchEngineStore.url(fromTemplate: template, query: query)
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parse(data, limit: limit)
        } catch {
            return []
        }
    }

    /// `["typed", ["one", "two"]]` — anything that isn't a string in the
    /// second element is dropped rather than failing the whole response, since
    /// Google appends its own metadata arrays after it.
    private static func parse(_ data: Data, limit: Int) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1
        else { return [] }

        if let suggestions = json[1] as? [String] {
            return Array(suggestions.prefix(limit))
        }
        if let mixed = json[1] as? [Any] {
            return Array(mixed.compactMap { $0 as? String }.prefix(limit))
        }
        return []
    }
}
