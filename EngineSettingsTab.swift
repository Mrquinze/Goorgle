import SwiftUI

/// Preferences → Engines: the `/keyword` search targets.
///
/// Edits are held in `@State` and written back to UserDefaults on every
/// change, so a half-typed template never has to be "saved" — but only valid
/// templates are offered as usable, and the row says why when one isn't.
struct EngineSettingsTab: View {
    @AppStorage(AppSettingsKeys.defaultEngine) private var defaultEngineID = "google"
    @State private var engines = SearchEngineStore.custom()
    @State private var selection: SearchEngine.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            defaultEnginePicker

            Divider()

            Text("Type /keyword followed by your search. Custom keywords take precedence over the built-in ones.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                Section("Your Engines") {
                    if engines.isEmpty {
                        Text("No custom engines yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($engines) { $engine in
                        EngineRow(engine: $engine)
                            .tag(engine.id)
                    }
                }

                Section("Built In") {
                    ForEach(SearchEngineStore.builtIn + SearchEngineStore.webEngines) { engine in
                        HStack {
                            Text("/\(engine.keyword)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 60, alignment: .leading)
                            Text(engine.name)
                            Spacer()
                            Text(host(of: engine.template))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: 8) {
                Button {
                    let new = SearchEngine(keyword: "", name: "New Engine", template: "https://example.com/search?q={query}")
                    engines.append(new)
                    selection = new.id
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    engines.removeAll { $0.id == selection }
                    selection = nil
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil || !engines.contains { $0.id == selection })

                Spacer()

                Text("\(SearchEngine.queryPlaceholder) is where your search goes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .onChange(of: engines) { _, updated in
            // Keywords are matched lowercased and without the slash, so
            // normalise here rather than at every lookup.
            let cleaned = updated.map { engine -> SearchEngine in
                var engine = engine
                engine.keyword = engine.keyword
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "/", with: "")
                    .lowercased()
                return engine
            }
            SearchEngineStore.saveCustom(cleaned)
        }
    }

    /// Which engine plain searches (and the live suggestions) go to. Custom
    /// engines are eligible too, as long as their template is usable.
    private var defaultEnginePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Search with", selection: $defaultEngineID) {
                ForEach(SearchEngineStore.selectableDefaults()) { engine in
                    Text(engine.name)
                        .tag(SearchEngineStore.defaultEngineID(for: engine))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Text(defaultEngineNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultEngineNote: String {
        let engine = SearchEngineStore.engine(forDefaultID: defaultEngineID)
        return engine.suggestTemplate == nil
            ? "\(engine.name) publishes no autocomplete API, so no live suggestions will appear — searching still works."
            : "Searches and live suggestions both go to \(engine.name)."
    }

    private func host(of template: String) -> String {
        URL(string: template.replacingOccurrences(of: SearchEngine.queryPlaceholder, with: "x"))?.host ?? ""
    }
}

private struct EngineRow: View {
    @Binding var engine: SearchEngine

    private var problem: String? {
        if SearchEngineStore.reservedKeywords.contains(engine.keyword.lowercased()) {
            return "/\(engine.keyword) is reserved for file search."
        }
        if engine.keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Needs a keyword."
        }
        if !SearchEngineStore.isValidTemplate(engine.template) {
            return "Needs an http(s) address containing \(SearchEngine.queryPlaceholder)."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("keyword", text: $engine.keyword)
                    .frame(width: 80)
                TextField("Name", text: $engine.name)
                    .frame(width: 120)
            }
            TextField("https://example.com/search?q=\(SearchEngine.queryPlaceholder)", text: $engine.template)
                .font(.system(size: 11, design: .monospaced))

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 3)
    }
}

#Preview {
    EngineSettingsTab()
}
