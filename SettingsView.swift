import SwiftUI

/// Preferences window content: General (icon visibility, shortcut, login item)
/// and Appearance (accent color, font) tabs — scaled-down take on DockDoor's
/// General/Appearance preferences split.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EngineSettingsTab()
                .tabItem { Label("Engines", systemImage: "magnifyingglass.circle") }
        }
        .frame(width: 480, height: 460)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettingsKeys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppSettingsKeys.showDockIcon) private var showDockIcon = false
    @AppStorage(AppSettingsKeys.menuBarIcon) private var menuBarIconRaw = MenuBarIconOption.magnifyingglass.rawValue
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var shortcut = HotKeyShortcut.stored()

    var body: some View {
        Form {
            Section("Icon Visibility") {
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
                    .disabled(showMenuBarIcon && !showDockIcon)
                Toggle("Show icon in Dock", isOn: $showDockIcon)
                    .disabled(showDockIcon && !showMenuBarIcon)
                Text("At least one must stay on so you can always reach Goorgle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar Icon") {
                Picker("Icon", selection: $menuBarIconRaw) {
                    ForEach(MenuBarIconOption.allCases) { option in
                        MenuBarIconLabel(option: option).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!showMenuBarIcon)
            }

            Section("Global Shortcut") {
                LabeledContent("Summon Goorgle") {
                    ShortcutRecorder(shortcut: $shortcut) { recorded in
                        recorded.store()
                        return AppDelegate.shared?.applyHotKeySettings() ?? false
                    }
                }
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        // Snap back if SMAppService refused (unsigned/DerivedData
                        // builds fail here), so the switch never claims a login
                        // item that doesn't exist.
                        let actual = LoginItemManager.setEnabled(wanted)
                        if actual != wanted { launchAtLogin = actual }
                    }
            }
        }
        .formStyle(.grouped)
        .onChange(of: showMenuBarIcon) { _, _ in AppDelegate.shared?.applyIconVisibilitySettings() }
        .onChange(of: showDockIcon) { _, _ in AppDelegate.shared?.applyIconVisibilitySettings() }
        .onChange(of: menuBarIconRaw) { _, _ in AppDelegate.shared?.applyMenuBarIconSettings() }
        // The status can change outside the app (System Settings → Login Items),
        // and this @State is only read once at init.
        .onAppear {
            launchAtLogin = LoginItemManager.isEnabled
            shortcut = HotKeyShortcut.stored()
        }
    }
}

/// Menu row for one icon choice: the glyph as it will actually appear in the
/// menu bar, next to its name.
private struct MenuBarIconLabel: View {
    let option: MenuBarIconOption

    var body: some View {
        HStack(spacing: 8) {
            if let image = option.statusItemImage() {
                Image(nsImage: image)
                    .renderingMode(option == .goorgleMark ? .original : .template)
            }
            Text(option.label)
        }
    }
}

private struct AppearanceSettingsTab: View {
    @AppStorage(AppSettingsKeys.accentColorHex) private var accentColorHex = "4D9EF5"
    @AppStorage(AppSettingsKeys.fontFamily) private var fontFamily = AppFont.systemToken
    @AppStorage(AppSettingsKeys.fontSize) private var fontSize = 15.0
    @AppStorage(AppSettingsKeys.theme) private var themeRaw = AppTheme.gradient.rawValue
    @AppStorage(AppSettingsKeys.colorMode) private var colorModeRaw = ColorMode.accent.rawValue
    @AppStorage(AppSettingsKeys.gradientAngle) private var gradientAngle = PanelPalette.defaultAngle
    @AppStorage(AppSettingsKeys.textColorMode) private var textColorModeRaw = TextColorMode.auto.rawValue
    @AppStorage(AppSettingsKeys.colorMenuBarIcon) private var colorMenuBarIcon = false

    /// Edited here and written straight through, since the stop list lives in
    /// UserDefaults as JSON rather than as an @AppStorage-able value.
    @State private var stopHexes: [String] = PanelPalette.storedStopHexes()

    private var theme: AppTheme { AppTheme.stored(themeRaw) }
    private var colorMode: ColorMode { ColorMode(rawValue: colorModeRaw) ?? .accent }
    private var palette: PanelPalette { PanelPalette.current() }

    /// Read once — enumerating every installed family on each redraw makes the
    /// picker visibly stutter on a Mac with a large Font Book.
    private let installedFamilies = AppFont.installedFamilies

    private var accentColor: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.hexString }
        )
    }

    private func stopBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: stopHexes.indices.contains(index) ? stopHexes[index] : "4D9EF5") },
            set: { newValue in
                guard stopHexes.indices.contains(index) else { return }
                stopHexes[index] = newValue.hexString
                saveStops()
            }
        )
    }

    private func saveStops() {
        PanelPalette.saveStopHexes(stopHexes)
        AppDelegate.shared?.applyMenuBarIconSettings()
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Style", selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(themeNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Colors") {
                Picker("Colors", selection: $colorModeRaw) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if colorMode == .accent {
                    ColorPicker("Accent color", selection: accentColor, supportsOpacity: false)
                    Text("The pill blends this one color toward white and black for its gradient.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    presetRow
                    stopEditor
                    angleSlider
                }

                Picker("Text", selection: $textColorModeRaw) {
                    ForEach(TextColorMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Color the menu bar icon", isOn: $colorMenuBarIcon)
                    .onChange(of: colorMenuBarIcon) { _, _ in
                        AppDelegate.shared?.applyMenuBarIconSettings()
                    }
            }

            Section("Font") {
                Picker("Family", selection: $fontFamily) {
                    ForEach(AppFont.systemChoices, id: \.token) { choice in
                        Text(choice.label).tag(choice.token)
                    }
                    Divider()
                    // Each family renders in itself, so the list reads like
                    // Font Book rather than a wall of identical names.
                    ForEach(installedFamilies, id: \.self) { family in
                        Text(family)
                            .font(.custom(family, size: 13))
                            .tag(family)
                    }
                }
                .pickerStyle(.menu)

                Stepper(value: $fontSize, in: 11...24, step: 1) {
                    Text("Size: \(Int(fontSize))pt")
                }
            }

            Section("Preview") {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme == .liquidGlass
                                         ? palette.tint
                                         : palette.foreground(for: theme).opacity(0.9))
                    Text("Search \(SearchEngineStore.defaultEngine().name) or type a URL")
                        .font(AppFont.font(family: fontFamily, size: fontSize))
                        .foregroundStyle(palette.foreground(for: theme))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .panelSurface(theme: theme, palette: palette, shape: .capsule,
                              tint: 0.34, shadow: 0.22, shadowRadius: 10)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        .formStyle(.grouped)
        .onChange(of: colorModeRaw) { _, _ in AppDelegate.shared?.applyMenuBarIconSettings() }
        .onChange(of: accentColorHex) { _, _ in AppDelegate.shared?.applyMenuBarIconSettings() }
        .onChange(of: gradientAngle) { _, _ in AppDelegate.shared?.applyMenuBarIconSettings() }
        .onAppear { stopHexes = PanelPalette.storedStopHexes() }
    }

    // MARK: - Multicolour controls

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(GradientPreset.all) { preset in
                    Button {
                        stopHexes = preset.hexes
                        gradientAngle = preset.angle
                        saveStops()
                    } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(gradient(for: preset))
                                .frame(height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(.primary.opacity(isSelected(preset) ? 0.65 : 0.15),
                                                lineWidth: isSelected(preset) ? 2 : 1)
                                )
                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(isSelected(preset) ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(preset.hexes.joined(separator: " → "))
                }
            }
        }
    }

    private var stopEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Colors in the gradient")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(stopHexes.indices, id: \.self) { index in
                    ColorPicker("", selection: stopBinding(index), supportsOpacity: false)
                        .labelsHidden()
                }

                Button {
                    // New stops start as a copy of the last one, so the
                    // gradient doesn't lurch somewhere unexpected before it's
                    // been picked.
                    stopHexes.append(stopHexes.last ?? "4D9EF5")
                    saveStops()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(stopHexes.count >= PanelPalette.maximumStops)

                Button {
                    stopHexes.removeLast()
                    saveStops()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(stopHexes.count <= PanelPalette.minimumStops)
            }
            .buttonStyle(.bordered)
        }
    }

    private var angleSlider: some View {
        HStack(spacing: 10) {
            // The arrow points the way the gradient actually flows. Angles run
            // clockwise from straight down, and SwiftUI's rotation is
            // clockwise too, hence the negation.
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(-gradientAngle))
                .frame(width: 16)

            Slider(value: $gradientAngle, in: 0...345, step: 15) {
                Text("Angle")
            }

            Text("\(Int(gradientAngle))°")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func gradient(for preset: GradientPreset) -> LinearGradient {
        let palette = PanelPalette(stops: preset.colors, angle: preset.angle, textMode: .auto)
        return palette.gradient
    }

    private func isSelected(_ preset: GradientPreset) -> Bool {
        stopHexes.map { $0.uppercased() } == preset.hexes.map { $0.uppercased() }
    }

    private var themeNote: String {
        switch theme {
        case .gradient:
            return colorMode == .accent
                ? "An opaque pill filled with your accent color."
                : "An opaque pill filled with your gradient."
        case .liquidGlass:
            return liquidGlassNote
        }
    }

    /// Liquid Glass proper is macOS 26; earlier systems get the older blur
    /// material tinted the same way, which is close but not the real
    /// refraction — worth saying rather than letting it look broken.
    private var liquidGlassNote: String {
        if #available(macOS 26.0, *) {
            return "Translucent glass that refracts the desktop behind it, tinted with your colors."
        }
        return "Translucent blur tinted with your colors. Full Liquid Glass needs macOS 26."
    }
}

#Preview {
    SettingsView()
}
