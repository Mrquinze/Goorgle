import SwiftUI
import AppKit

/// Android 16 (Material 3 expressive) style search bar: a large, fully
/// rounded pill with a leading search glyph and a trailing engine mark, over a
/// gradient derived from the user's accent color (SettingsView). Results —
/// live suggestions from the chosen engine, or Spotlight file hits in `/file`
/// mode — expand below the pill as a matching rounded card, and the panel
/// resizes to fit.
struct SearchBarView: View {
    /// The panel's "focus the field now" signal. Every presentation bumps it,
    /// including one after the window has actually become key — `onAppear`
    /// alone fires while the panel is still on its way up, and SwiftUI drops a
    /// focus request made before there's a key window to put it in.
    @ObservedObject var focus: SearchFocus = SearchFocus()
    var onDismiss: () -> Void
    /// Reports the height the panel should be, so it can hug its content
    /// instead of reserving space for the largest possible result list.
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var query = ""
    @State private var rows: [ResultRow] = []
    @State private var highlightedIndex: Int?
    @State private var hoveredIndex: Int?
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

    /// Not read directly any more — the palette resolves colors — but kept as
    /// an observed dependency so changing the accent redraws the pill.
    @AppStorage(AppSettingsKeys.accentColorHex) private var accentColorHex = "4D9EF5"
    @AppStorage(AppSettingsKeys.fontFamily) private var fontFamily = AppFont.systemToken
    @AppStorage(AppSettingsKeys.fontSize) private var fontSize = 15.0
    @AppStorage(AppSettingsKeys.defaultEngine) private var defaultEngineID = "google"
    @AppStorage(AppSettingsKeys.theme) private var themeRaw = AppTheme.gradient.rawValue
    @AppStorage(AppSettingsKeys.colorMode) private var colorModeRaw = ColorMode.accent.rawValue
    @AppStorage(AppSettingsKeys.textColorMode) private var textColorModeRaw = TextColorMode.auto.rawValue
    @AppStorage(AppSettingsKeys.gradientAngle) private var gradientAngle = PanelPalette.defaultAngle
    /// The stop list is JSON, which `@AppStorage` can't observe; this counter
    /// is bumped whenever it's saved so the dependency exists anyway.
    @AppStorage(AppSettingsKeys.paletteRevision) private var paletteRevision = 0

    private var theme: AppTheme { AppTheme.stored(themeRaw) }

    /// Rebuilt whenever any color setting changes. The `@AppStorage` properties
    /// above exist so SwiftUI redraws on those changes — the stop list itself
    /// is JSON, which `@AppStorage` can't observe, so the mode/angle/text
    /// properties carry the dependency for it.
    private var palette: PanelPalette { PanelPalette.current() }

    /// Where plain (unprefixed) searches go, and where suggestions come from.
    /// Read through the store so a deleted custom engine falls back to Google
    /// rather than leaving searches with nowhere to land.
    private var defaultEngine: SearchEngine {
        SearchEngineStore.engine(forDefaultID: defaultEngineID)
    }

    static let width: CGFloat = 420
    private static let suggestionLimit = 5
    private static let fileLimit = 6
    /// `/f` is the short form; both need the trailing space before a term.
    private static let filePrefixes = ["/file", "/f"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pill

            if !rows.isEmpty {
                resultsCard
            } else if let hint = hintText {
                hintCard(hint)
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .top)
        .background(heightReporter)
        .animation(.easeOut(duration: 0.14), value: rows)
        .onAppear { isFocused = true }
        .onChange(of: focus.token) { _, _ in isFocused = true }
        .onExitCommand { onDismiss() }
        .onMoveCommand(perform: handleMoveCommand)
        .task(id: query) { await loadRows() }
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 12) {
            Image(systemName: modeChip?.symbol ?? "magnifyingglass")
                .foregroundStyle(glyphColor)
                .font(.system(size: 16, weight: .medium))
                .contentTransition(.symbolEffect(.replace))

            if let modeChip {
                Text(modeChip.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(foreground.opacity(0.18)))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .transition(.scale.combined(with: .opacity))
            }

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(searchFont)
                .foregroundStyle(foreground)
                .tint(foreground)
                .focused($isFocused)
                .onSubmit(activateSelection)
                // The field editor swallows arrows (they move the insertion
                // point) and Escape before either reaches the enclosing view's
                // onMoveCommand/onExitCommand, so intercept them on the field
                // itself; `.handled` stops them from also moving the caret.
                .onKeyPress(.upArrow) { moveHighlight(.up); return .handled }
                .onKeyPress(.downArrow) { moveHighlight(.down); return .handled }
                .onKeyPress(.escape) { onDismiss(); return .handled }

            trailingAccessory
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .panelSurface(theme: theme, palette: palette, shape: .capsule,
                      tint: 0.34, shadow: 0.3, shadowRadius: 14)
        .animation(.easeOut(duration: 0.16), value: modeChip?.label)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(foreground)
                .frame(width: 20, height: 20)
        } else if !query.isEmpty {
            Button {
                query = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(foreground.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clear")
        } else {
            engineMark
        }
    }

    /// The Google mark is Goorgle's whole visual joke, but wearing it while
    /// searching DuckDuckGo would be a lie about where the query goes — other
    /// engines get a monogram in the same spot.
    @ViewBuilder
    private var engineMark: some View {
        if defaultEngine.keyword == "google" {
            GoogleGMark()
                .frame(width: 20, height: 20)
        } else {
            Text(String(defaultEngine.name.prefix(1)).uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(foreground.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(foreground.opacity(0.18)))
                .help("Searching \(defaultEngine.name)")
        }
    }

    // MARK: - Results

    private var resultsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                resultRow(row, at: index)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(foreground.opacity(0.12))
                        .padding(.horizontal, 12)
                }
            }

            footer
        }
        .padding(.vertical, 4)
        .panelSurface(theme: theme, palette: palette, shape: .rounded(16),
                      tint: 0.26, shadow: 0.22, shadowRadius: 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func resultRow(_ row: ResultRow, at index: Int) -> some View {
        Button {
            activate(row)
        } label: {
            HStack(spacing: 10) {
                rowIcon(for: row)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(AppFont.font(family: fontFamily, size: fontSize - 1))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(foreground.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }

                Spacer(minLength: 8)

                if index == highlightedIndex || index == hoveredIndex {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(foreground.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Without an explicit shape the row is only clickable where it has
            // actually drawn something — the gaps between glyphs swallowed
            // clicks and the row felt dead.
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(rowHighlight(at: index))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
        .help(row.helpText)
    }

    @ViewBuilder
    private func rowIcon(for row: ResultRow) -> some View {
        switch row {
        case .calculation:
            Image(systemName: "equal.square.fill")
                .font(.system(size: 13))
                .foregroundStyle(foreground.opacity(0.85))
                .frame(width: 18, height: 18)
        case .suggestion:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(foreground.opacity(0.7))
                .frame(width: 18, height: 18)
        case .file(let hit):
            Image(nsImage: NSWorkspace.shared.icon(forFile: hit.url.path))
                .resizable()
                .frame(width: 18, height: 18)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(primaryActionHint)
            Text("↑↓ select")
            if isFileMode {
                Text("⌥↩ reveal in Finder")
            }
            Spacer()
            Text("⎋ close")
        }
        .font(.system(size: 10))
        .foregroundStyle(foreground.opacity(0.55))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func hintCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground.opacity(0.75))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface(theme: theme, palette: palette, shape: .rounded(14),
                      tint: 0.2, shadow: 0.16, shadowRadius: 8)
        .transition(.opacity)
    }

    /// Reports the laid-out height to the panel. A zero-size background view
    /// measures without influencing the layout it's measuring.
    private var heightReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { _, height in
                    onContentHeightChange(height)
                }
        }
    }

    // MARK: - Mode

    /// What the current text means: a file search, a `/keyword` engine
    /// search, or an ordinary web search.
    private enum Intent: Equatable {
        case files(String)
        case engine(SearchEngine, String)
        case web(String)
    }

    /// Parsed once per body evaluation; every mode-dependent bit of the view
    /// reads it rather than re-scanning the prefixes.
    private var intent: Intent {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return .web(trimmed) }

        let withoutSlash = String(trimmed.dropFirst())
        let keyword = String(withoutSlash.prefix { !$0.isWhitespace })
        let term = withoutSlash
            .dropFirst(keyword.count)
            .trimmingCharacters(in: .whitespaces)

        if Self.filePrefixes.contains(keyword.lowercased()) { return .files(term) }
        if let engine = SearchEngineStore.engine(forKeyword: keyword) { return .engine(engine, term) }
        // An unknown /word is just text — searching for it beats silently
        // eating the slash.
        return .web(trimmed)
    }

    private var isFileMode: Bool {
        if case .files = intent { return true }
        return false
    }

    /// The chip shown inside the pill, if this isn't a plain web search.
    private var modeChip: (label: String, symbol: String)? {
        switch intent {
        case .files: return ("Files", "folder.fill")
        case .engine(let engine, _): return (engine.name, "arrow.up.right.square.fill")
        case .web: return nil
        }
    }

    /// What Return does right now — which depends on the mode *and* on whether
    /// the highlighted row is a calculated answer.
    private var primaryActionHint: String {
        if let highlightedIndex, rows.indices.contains(highlightedIndex),
           case .calculation = rows[highlightedIndex] {
            return "↩ copy"
        }
        switch intent {
        case .files: return "↩ open"
        case .engine(let engine, _): return "↩ search \(engine.name)"
        case .web:
            if case .calculation = rows.first, highlightedIndex == nil, rows.count == 1 {
                return "↩ search · click to copy"
            }
            return "↩ search"
        }
    }

    private var placeholder: String {
        switch intent {
        case .files: return "Search files on this Mac"
        case .engine(let engine, _): return "Search \(engine.name)"
        case .web: return "Search \(defaultEngine.name) or type a URL"
        }
    }

    private var hintText: String? {
        switch intent {
        case .files:
            return "Keep typing — file search needs at least two characters."
        case .engine(let engine, let term) where term.isEmpty:
            return "Type what to look up on \(engine.name)."
        case .web(let term) where term.isEmpty:
            return "Searching \(defaultEngine.name). Try /file for files, /yt or /ddg to search elsewhere, or 12*34 to calculate."
        default:
            return nil
        }
    }

    // MARK: - Styling

    /// Chosen for contrast against the whole palette (or forced, if the user
    /// overrode it); on glass it defaults to the system label color, which is
    /// what the material is tuned for.
    private var foreground: Color {
        palette.foreground(for: theme)
    }

    /// The leading glyph carries the palette on glass, where the surface itself
    /// is only lightly tinted and would otherwise show no color at all.
    private var glyphColor: Color {
        theme == .liquidGlass ? palette.tint : foreground.opacity(0.9)
    }

    private var searchFont: Font {
        AppFont.font(family: fontFamily, size: fontSize)
    }

    private func rowHighlight(at index: Int) -> Color {
        if index == highlightedIndex { return palette.highlight(for: theme, strength: 0.22) }
        if index == hoveredIndex { return palette.highlight(for: theme, strength: 0.12) }
        return .clear
    }

    // MARK: - Keyboard

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .down: moveHighlight(.down)
        case .up: moveHighlight(.up)
        default: break
        }
    }

    private enum HighlightMove { case up, down }

    private func moveHighlight(_ move: HighlightMove) {
        guard !rows.isEmpty else { return }
        switch move {
        case .down:
            let next = (highlightedIndex ?? -1) + 1
            highlightedIndex = min(next, rows.count - 1)
        case .up:
            let previous = (highlightedIndex ?? 0) - 1
            highlightedIndex = previous < 0 ? nil : previous
        }
    }

    // MARK: - Loading

    private func loadRows() async {
        let intent = intent
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            rows = []
            highlightedIndex = nil
            isLoading = false
            return
        }

        // Arithmetic and offline conversions resolve instantly, so show the
        // answer before the network debounce rather than after it.
        var answer: [ResultRow] = []
        if case .web(let term) = intent, let calculation = Calculator.evaluate(term) {
            answer = [.calculation(calculation)]
            rows = answer
            highlightedIndex = nil
        }

        // Debounce: SwiftUI's .task(id:) cancels this automatically when
        // `query` changes again before the sleep finishes.
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }

        let loaded: [ResultRow]
        switch intent {
        case .files(let term):
            guard term.count >= 2 else {
                rows = []
                highlightedIndex = nil
                return
            }
            isLoading = true
            loaded = await FileSearchClient.shared
                .search(term, limit: Self.fileLimit)
                .map(ResultRow.file)

        case .engine(_, let term), .web(let term):
            isLoading = true
            // A currency pair needs live rates, so unlike the offline
            // calculations it can only join the list after an await.
            if answer.isEmpty, case .web = intent,
               let request = Calculator.currencyRequest(term),
               let converted = await CurrencyRatesClient.shared.convert(request) {
                answer = [.calculation(converted)]
            }
            // A /keyword engine that publishes its own autocomplete uses it;
            // one that doesn't (YouTube, GitHub) borrows the default engine's,
            // which still autocompletes the term usefully.
            var suggestionSource = defaultEngine
            if case .engine(let engine, _) = intent, engine.suggestTemplate != nil {
                suggestionSource = engine
            }
            let suggestions = await SuggestionsClient
                .fetch(for: term, from: suggestionSource, limit: Self.suggestionLimit)
                .map(ResultRow.suggestion)
            loaded = answer + suggestions
        }

        // Leave `isLoading` alone when cancelled: the task that replaced this
        // one has already set it, and clearing it here would hide the spinner
        // for a load that's still running.
        if Task.isCancelled { return }
        isLoading = false
        rows = loaded
        highlightedIndex = nil
    }

    // MARK: - Actions

    private func activateSelection() {
        if let highlightedIndex, rows.indices.contains(highlightedIndex) {
            activate(rows[highlightedIndex])
            return
        }
        switch intent {
        case .files:
            // Return with nothing highlighted opens the top file hit; there's
            // no sensible "search the web for /file foo" fallback here.
            if let first = rows.first { activate(first) }
        case .engine(let engine, let term):
            submit(term, to: engine)
        case .web(let term):
            searchWeb(for: term)
        }
    }

    private func activate(_ row: ResultRow) {
        switch row {
        case .suggestion(let text):
            // In engine mode a suggestion is a *term*, not a destination: the
            // whole point of /yt is that everything goes to that engine.
            if case .engine(let engine, _) = intent {
                submit(text, to: engine)
            } else {
                searchWeb(for: text)
            }
        case .calculation(let calculation):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.copyValue, forType: .string)
            dismissAndReset()
        case .file(let hit):
            // Option means "show me where it lives" rather than "open it" —
            // the same convention as Spotlight.
            if NSEvent.modifierFlags.contains(.option) {
                NSWorkspace.shared.activateFileViewerSelecting([hit.url])
            } else {
                NSWorkspace.shared.open(hit.url)
            }
            dismissAndReset()
        }
    }

    private func submit(_ term: String, to engine: SearchEngine) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = SearchEngineStore.url(for: engine, query: trimmed) else { return }
        NSWorkspace.shared.open(url)
        dismissAndReset()
    }

    private func searchWeb(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.destination(for: trimmed, using: defaultEngine) else { return }
        NSWorkspace.shared.open(url)
        dismissAndReset()
    }

    /// Where a piece of text should send the browser: itself if it's already a
    /// web URL, `https://` + itself if it reads as a bare domain, a search on
    /// the chosen engine otherwise.
    ///
    /// Only http and https are ever handed to `NSWorkspace`. The text here
    /// isn't always typed by the user — a suggestion row carries whatever the
    /// remote endpoint returned — and `NSWorkspace.open` will happily hand a
    /// `file:`, `ftp:` or third-party-app scheme to whatever app claims it.
    /// Confining the URL branch to the two web schemes keeps this from being a
    /// way to poke at local handlers.
    static func destination(for text: String, using engine: SearchEngine) -> URL? {
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host?.isEmpty == false {
            return url
        }
        // A bare domain: no spaces, no scheme, and something that parses as a
        // dotted host ("apple.com", "docs.rs/serde"). Note `hasPrefix("http")`
        // was the old test, which also matched "httpfoo.com" and then opened
        // it as a scheme-less URL that went nowhere.
        if !text.contains(" "), text.contains("."), !text.contains(":"),
           let url = URL(string: "https://\(text)"),
           let host = url.host, host.contains(".") {
            return url
        }
        return SearchEngineStore.url(for: engine, query: text)
    }

    private func dismissAndReset() {
        query = ""
        rows = []
        highlightedIndex = nil
        onDismiss()
    }
}

/// One row under the pill: a calculated answer, an engine suggestion, or a
/// Spotlight file hit.
enum ResultRow: Identifiable, Equatable {
    case calculation(CalcResult)
    case suggestion(String)
    case file(FileHit)

    var id: String {
        switch self {
        case .calculation(let result): return "c:\(result.detail)=\(result.display)"
        case .suggestion(let text): return "s:\(text)"
        case .file(let hit): return "f:\(hit.url.path)"
        }
    }

    var title: String {
        switch self {
        case .calculation(let result): return result.display
        case .suggestion(let text): return text
        case .file(let hit): return hit.name
        }
    }

    var subtitle: String? {
        switch self {
        case .calculation(let result): return result.detail
        case .suggestion: return nil
        case .file(let hit): return hit.folder
        }
    }

    var helpText: String {
        switch self {
        case .calculation(let result): return "Copy \(result.copyValue)"
        case .suggestion(let text): return "Search for “\(text)”"
        case .file(let hit): return hit.url.path
        }
    }
}

#Preview {
    SearchBarView(onDismiss: {})
}
