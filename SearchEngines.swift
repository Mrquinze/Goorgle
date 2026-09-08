import Foundation

/// A search target: the engine plain searches go to, and/or a `/keyword` one
/// like `/yt cats` → YouTube's results for "cats".
struct SearchEngine: Codable, Identifiable, Hashable {
    var id: UUID
    /// Typed after the slash, without it. Lowercased on save.
    var keyword: String
    var name: String
    /// URL with `{query}` where the (percent-encoded) term goes.
    var template: String
    /// OpenSearch autocomplete endpoint, same placeholder. Nil for engines
    /// that don't publish one — the pill then shows no suggestion rows.
    var suggestTemplate: String?

    init(id: UUID = UUID(), keyword: String, name: String, template: String, suggestTemplate: String? = nil) {
        self.id = id
        self.keyword = keyword
        self.name = name
        self.template = template
        self.suggestTemplate = suggestTemplate
    }

    static let queryPlaceholder = "{query}"
}

/// Built-in engines plus whatever the user added in Preferences → Engines.
enum SearchEngineStore {
    /// `file`/`f` are Goorgle's own file-search mode, so an engine can't claim
    /// them — the mode check runs first and the engine would simply never fire.
    static let reservedKeywords = ["file", "f"]

    /// General web engines: any of these can be *the* default for plain
    /// searches, and each is also reachable ad hoc by its keyword (`/ddg cats`
    /// searches DuckDuckGo once without changing the default).
    static let webEngines: [SearchEngine] = [
        SearchEngine(
            id: uuid(1), keyword: "google", name: "Google",
            template: "https://www.google.com/search?q={query}",
            suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q={query}"
        ),
        SearchEngine(
            id: uuid(2), keyword: "ddg", name: "DuckDuckGo",
            template: "https://duckduckgo.com/?q={query}",
            suggestTemplate: "https://duckduckgo.com/ac/?q={query}&type=list"
        ),
        SearchEngine(
            id: uuid(3), keyword: "brave", name: "Brave Search",
            template: "https://search.brave.com/search?q={query}",
            suggestTemplate: "https://search.brave.com/api/suggest?q={query}"
        ),
        SearchEngine(
            id: uuid(4), keyword: "bing", name: "Bing",
            template: "https://www.bing.com/search?q={query}",
            suggestTemplate: "https://api.bing.com/osjson.aspx?query={query}"
        ),
        SearchEngine(
            id: uuid(5), keyword: "ecosia", name: "Ecosia",
            template: "https://www.ecosia.org/search?q={query}",
            suggestTemplate: "https://ac.ecosia.org/autocomplete?q={query}&type=list"
        ),
        SearchEngine(
            id: uuid(6), keyword: "startpage", name: "Startpage",
            template: "https://www.startpage.com/sp/search?query={query}"
        ),
        SearchEngine(
            id: uuid(7), keyword: "yahoo", name: "Yahoo",
            template: "https://search.yahoo.com/search?p={query}",
            suggestTemplate: "https://sugg.search.yahoo.net/sg/?output=fxjson&command={query}"
        ),
        SearchEngine(
            id: uuid(8), keyword: "mojeek", name: "Mojeek",
            template: "https://www.mojeek.com/search?q={query}"
        ),
        SearchEngine(
            id: uuid(9), keyword: "marginalia", name: "Marginalia",
            template: "https://marginalia-search.com/search?query={query}"
        ),
        SearchEngine(
            id: uuid(10), keyword: "swisscows", name: "Swisscows",
            template: "https://swisscows.com/en/web?query={query}"
        ),
        SearchEngine(
            id: uuid(11), keyword: "kagi", name: "Kagi",
            template: "https://kagi.com/search?q={query}"
        ),
        // Answer engines rather than result lists. They take the same
        // `?q=` handoff, so they slot in as ordinary engines — including as
        // the default, for anyone who'd rather ask than search.
        SearchEngine(
            id: uuid(12), keyword: "ppl", name: "Perplexity",
            template: "https://www.perplexity.ai/search?q={query}"
        ),
        SearchEngine(
            id: uuid(13), keyword: "gpt", name: "ChatGPT",
            template: "https://chatgpt.com/?q={query}"
        ),
        SearchEngine(
            id: uuid(14), keyword: "claude", name: "Claude",
            template: "https://claude.ai/new?q={query}"
        ),
    ]

    /// Site-specific `/keyword` engines. Not offered as a default, since
    /// "search everything on YouTube" isn't a sane general setting.
    static let builtIn: [SearchEngine] = [
        SearchEngine(id: uuid(21), keyword: "yt", name: "YouTube",
                     template: "https://www.youtube.com/results?search_query={query}"),
        SearchEngine(id: uuid(22), keyword: "gh", name: "GitHub",
                     template: "https://github.com/search?q={query}"),
        SearchEngine(id: uuid(23), keyword: "wiki", name: "Wikipedia",
                     template: "https://en.wikipedia.org/w/index.php?search={query}"),
        SearchEngine(id: uuid(24), keyword: "maps", name: "Maps",
                     template: "https://www.google.com/maps/search/{query}"),
        SearchEngine(id: uuid(25), keyword: "so", name: "Stack Overflow",
                     template: "https://stackoverflow.com/search?q={query}"),
    ]

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    // MARK: - Default engine

    /// The engine plain (unprefixed) searches and the live suggestions use.
    /// Falls back to Google if the stored pick has since been deleted.
    static func defaultEngine(from defaults: UserDefaults = .standard) -> SearchEngine {
        engine(forDefaultID: defaults.string(forKey: AppSettingsKeys.defaultEngine) ?? "", from: defaults)
    }

    /// Resolves a stored default-engine identifier. Separate from
    /// `defaultEngine()` so SearchBarView can resolve its own `@AppStorage`
    /// value — that way SwiftUI sees the dependency and redraws the pill when
    /// the engine changes, instead of the store silently re-reading defaults.
    static func engine(forDefaultID id: String, from defaults: UserDefaults = .standard) -> SearchEngine {
        if let match = webEngines.first(where: { $0.keyword == id }) { return match }
        if let match = custom(from: defaults).first(where: { $0.id.uuidString == id }) { return match }
        return webEngines[0]
    }

    /// Identifier stored for a default-engine pick: the keyword for built-in
    /// web engines (stable across releases) and the UUID for a custom one
    /// (whose keyword the user can rename at any time).
    static func defaultEngineID(for engine: SearchEngine) -> String {
        webEngines.contains(engine) ? engine.keyword : engine.id.uuidString
    }

    /// Everything eligible to *be* the default: the built-in web engines plus
    /// any custom engine complete enough to use.
    static func selectableDefaults() -> [SearchEngine] {
        webEngines + custom().filter { isValidTemplate($0.template) }
    }

    // MARK: - Custom engines

    static func custom(from defaults: UserDefaults = .standard) -> [SearchEngine] {
        guard let data = defaults.data(forKey: AppSettingsKeys.customEngines),
              let engines = try? JSONDecoder().decode([SearchEngine].self, from: data)
        else { return [] }
        return engines
    }

    static func saveCustom(_ engines: [SearchEngine], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(engines) else { return }
        defaults.set(data, forKey: AppSettingsKeys.customEngines)
    }

    /// Custom engines come first so a user keyword can shadow a built-in one.
    static func all() -> [SearchEngine] {
        custom() + builtIn + webEngines
    }

    static func engine(forKeyword keyword: String) -> SearchEngine? {
        let needle = keyword.lowercased()
        guard !reservedKeywords.contains(needle) else { return nil }
        return all().first { $0.keyword.lowercased() == needle }
    }

    // MARK: - URLs

    static func url(for engine: SearchEngine, query: String) -> URL? {
        url(fromTemplate: engine.template, query: query)
    }

    /// Builds a URL from a `{query}` template, or nil if it doesn't produce a
    /// usable web address.
    ///
    /// Templates are user-authored text that ends up at `NSWorkspace.open`, so
    /// the result is confined to http/https here exactly as typed queries are
    /// — a template of `file:///{query}` or `someapp://{query}` would otherwise
    /// be a way to hand arbitrary URLs to whatever app claims that scheme.
    static func url(fromTemplate template: String, query: String) -> URL? {
        guard let encoded = QueryEncoding.percentEncoded(query) else { return nil }
        let filled = template.replacingOccurrences(of: SearchEngine.queryPlaceholder, with: encoded)
        guard let url = URL(string: filled),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Whether a template is worth saving: it has to carry the placeholder and
    /// resolve to a real web URL for a sample term.
    static func isValidTemplate(_ template: String) -> Bool {
        guard template.contains(SearchEngine.queryPlaceholder) else { return false }
        return url(fromTemplate: template, query: "test") != nil
    }
}
