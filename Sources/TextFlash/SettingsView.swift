import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var hasAccessibilityPermission = EventController.shared.checkPermission()
    @State private var launchAtLogin = LoginItemController.isEnabled
    @State private var settingsErrorMessage: String?
    @State private var showUnicodeApps = false
    @State private var unicodeAppsCount = EventController.shared.unicodeBundleIDs.count
    @State private var showExclusions = false
    @State private var exclusionsCount = EventController.shared.excludedBundleIDs.count

    var body: some View {
        ZStack {
            SettingsPalette.window
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                headerBlock

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 10) {
                            languageSection
                            launchSection
                            timingSection
                            unicodeAppsSection
                            permissionSection
                            exclusionSection
                        }
                        .padding(10)
                        .glassContainer(cornerRadius: 16)
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(18)
        }
        .frame(width: 620, height: 560)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showUnicodeApps) {
            UnicodeAppsSettingsView()
        }
        .sheet(isPresented: $showExclusions) {
            ExcludedAppsSettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .textFlashUnicodeAppsDidChange)) { _ in
            unicodeAppsCount = EventController.shared.unicodeBundleIDs.count
        }
        .onReceive(NotificationCenter.default.publisher(for: .textFlashExclusionsDidChange)) { _ in
            exclusionsCount = EventController.shared.excludedBundleIDs.count
        }
        .alert(L10n.t("settings.launch.failed.title"), isPresented: Binding(
            get: { settingsErrorMessage != nil },
            set: { if !$0 { settingsErrorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { settingsErrorMessage = nil }
        } message: {
            Text(settingsErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("settings.title"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                Text(L10n.t("settings.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(SettingsPalette.secondaryText)
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(0)

            statusSummary
        }
        .padding(16)
        .glassContainer(cornerRadius: 16)
    }

    private var statusSummary: some View {
        HStack(spacing: 10) {
            SummaryPill(
                icon: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                title: L10n.t("settings.permission.title"),
                value: hasAccessibilityPermission ? L10n.t("debug.enabled") : L10n.t("settings.status.required"),
                tint: hasAccessibilityPermission ? SettingsPalette.success : SettingsPalette.warning
            )
            SummaryPill(
                icon: "keyboard.badge.ellipsis",
                title: L10n.t("settings.unicodeApps.title"),
                value: "\(unicodeAppsCount)",
                tint: SettingsPalette.accent
            )
            SummaryPill(
                icon: "nosign.app",
                title: L10n.t("settings.exclusions.title"),
                value: "\(exclusionsCount)",
                tint: SettingsPalette.secondaryText
            )
        }
    }

    private var languageSection: some View {
        SettingsSection(
            icon: "globe",
            title: L10n.t("settings.language.title"),
            subtitle: L10n.t("settings.language.subtitle")
        ) {
            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        settings.language = language
                    } label: {
                        if settings.language == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(settings.language.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SettingsPalette.mutedText)
                }
                .foregroundColor(SettingsPalette.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SettingsPalette.glass)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsPalette.border))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 150, alignment: .trailing)
        }
    }

    private var permissionSection: some View {
        SettingsSection(
            icon: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
            title: L10n.t("settings.permission.title"),
            subtitle: hasAccessibilityPermission
                ? L10n.t("settings.permission.enabled")
                : L10n.t("settings.permission.disabled"),
            action: requestAccessibilityPermission
        ) {
            Button {
                requestAccessibilityPermission()
            } label: {
                Label(
                    hasAccessibilityPermission
                        ? L10n.t("settings.permission.authorizedButton")
                        : L10n.t("settings.permission.button"),
                    systemImage: hasAccessibilityPermission ? "checkmark.circle" : "lock.open"
                )
            }
        }
    }

    private var launchSection: some View {
        SettingsSection(
            icon: "power",
            title: L10n.t("settings.launch.title"),
            subtitle: L10n.t("settings.launch.subtitle")
        ) {
            Toggle(L10n.t("settings.launch.toggle"), isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LoginItemController.setEnabled(enabled)
                        launchAtLogin = LoginItemController.isEnabled
                    } catch {
                        launchAtLogin = LoginItemController.isEnabled
                        settingsErrorMessage = error.localizedDescription
                    }
                }
            ))
            .toggleStyle(.switch)
        }
    }

    private var timingSection: some View {
        SettingsSection(
            icon: "timer",
            title: L10n.t("settings.timing.title"),
            subtitle: L10n.t("settings.timing.subtitle")
        ) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(L10n.f("settings.timing.delay", settings.deletionSettleDelayPerCharacter))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Slider(value: $settings.deletionSettleDelayPerCharacter, in: 5...80, step: 5)
                    .frame(width: 180)
                Text(L10n.f("settings.timing.effective", settings.deletionSettleDelayPerCharacter * 3))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var unicodeAppsSection: some View {
        SettingsSection(
            icon: "keyboard.badge.ellipsis",
            title: L10n.t("settings.unicodeApps.title"),
            subtitle: L10n.t("settings.unicodeApps.subtitle"),
            action: { showUnicodeApps = true }
        ) {
            HStack(spacing: 8) {
                InfoPopoverButton(
                    title: L10n.t("settings.unicodeApps.info.title"),
                    message: L10n.t("settings.unicodeApps.info.message")
                )

                Text("\(unicodeAppsCount)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Button(L10n.t("settings.unicodeApps.manage")) {
                    showUnicodeApps = true
                }
            }
        }
    }

    private var exclusionSection: some View {
        SettingsSection(
            icon: "nosign.app",
            title: L10n.t("settings.exclusions.title"),
            subtitle: L10n.t("settings.exclusions.subtitle"),
            action: { showExclusions = true }
        ) {
            HStack(spacing: 8) {
                InfoPopoverButton(
                    title: L10n.t("settings.exclusions.info.title"),
                    message: L10n.t("settings.exclusions.info.message")
                )

                Text("\(exclusionsCount)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Button(L10n.t("settings.exclusions.manage")) {
                    showExclusions = true
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        let granted = EventController.shared.requestPermission()
        if !granted {
            EventController.openAccessibilitySettings()
        }
        hasAccessibilityPermission = EventController.shared.checkPermission()
    }
}

private struct InfoPopoverButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 260, alignment: .leading)
            .padding(14)
            .preferredColorScheme(.light)
        }
    }
}

private struct UnicodeAppsSettingsView: View {
    var body: some View {
        ManagedApplicationsSettingsView(configuration: .unicodeInput)
    }
}

private struct ExcludedAppsSettingsView: View {
    var body: some View {
        ManagedApplicationsSettingsView(configuration: .exclusions)
    }
}

private struct ManagedApplicationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: ManagedApplicationsConfiguration
    @State private var bundleIDs: [String]
    @State private var errorMessage: String?

    init(configuration: ManagedApplicationsConfiguration) {
        self.configuration = configuration
        _bundleIDs = State(initialValue: configuration.bundleIDs.sorted())
    }

    var body: some View {
        ZStack {
            SettingsPalette.window
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassContainer(cornerRadius: 16)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: configuration.notificationName)) { _ in
            refresh()
        }
        .alert(L10n.t(configuration.addFailedTitleKey), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: configuration.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SettingsPalette.accent)
                .frame(width: 30, height: 30)
                .background(SettingsPalette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(L10n.t(configuration.titleKey))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SettingsPalette.primaryText)

            Spacer()

            HStack(spacing: 6) {
                sheetIconButton("scope", help: L10n.t(configuration.addCurrentKey)) {
                    addCurrentApplication()
                }

                sheetIconButton("plus", help: L10n.t(configuration.chooseKey)) {
                    chooseApplication()
                }

                sheetIconButton("trash", help: L10n.t(configuration.clearKey), disabled: bundleIDs.isEmpty) {
                    clearAll()
                }

                Button(L10n.t("common.done")) {
                    dismiss()
                }
                .buttonStyle(SheetDoneButtonStyle())
            }
        }
        .padding(14)
        .glassContainer(cornerRadius: 14)
    }

    @ViewBuilder
    private var content: some View {
        if bundleIDs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: configuration.emptyIcon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(SettingsPalette.mutedText.opacity(0.55))
                Text(L10n.t(configuration.emptyKey))
                    .font(.system(size: 13))
                    .foregroundColor(SettingsPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        appRow(bundleID)
                    }
                }
                .padding(10)
            }
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon(for: bundleID))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .frame(width: 28, height: 28)
                .background(SettingsPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.border))

            VStack(alignment: .leading, spacing: 2) {
                Text(appName(for: bundleID))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                Text(bundleID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SettingsPalette.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                remove(bundleID)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SettingsPalette.warning)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(L10n.t(configuration.removeKey))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(SettingsPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.border))
    }

    private func sheetIconButton(
        _ symbol: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(disabled ? SettingsPalette.mutedText.opacity(0.55) : SettingsPalette.secondaryText)
                .frame(width: 30, height: 30)
                .background(SettingsPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsPalette.border))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.t(configuration.chooseKey)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK else { return }
        var values = configuration.bundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                values.insert(bundleID)
            }
        }
        configuration.setBundleIDs(values)
        refresh()
    }

    private func addCurrentApplication() {
        guard let app = EventController.shared.exclusionTargetApplication() else {
            errorMessage = L10n.t(configuration.addFailedMessageKey)
            return
        }
        var values = configuration.bundleIDs
        values.insert(app.bundleID)
        configuration.setBundleIDs(values)
        refresh()
    }

    private func remove(_ bundleID: String) {
        var values = configuration.bundleIDs
        values.remove(bundleID)
        configuration.setBundleIDs(values)
        refresh()
    }

    private func clearAll() {
        configuration.setBundleIDs([])
        refresh()
    }

    private func refresh() {
        bundleIDs = configuration.bundleIDs.sorted()
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return bundleID
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func appIcon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }
}

private enum ManagedApplicationsConfiguration {
    case unicodeInput
    case exclusions

    var titleKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.title"
        case .exclusions: return "exclusions.title"
        }
    }

    var chooseKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.choose"
        case .exclusions: return "exclusions.choose"
        }
    }

    var addCurrentKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.addCurrent"
        case .exclusions: return "exclusions.addCurrent"
        }
    }

    var clearKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.clear"
        case .exclusions: return "exclusions.clear"
        }
    }

    var emptyKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.empty"
        case .exclusions: return "exclusions.empty"
        }
    }

    var removeKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.remove"
        case .exclusions: return "exclusions.remove"
        }
    }

    var addFailedTitleKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.addFailed.title"
        case .exclusions: return "exclusions.addFailed.title"
        }
    }

    var addFailedMessageKey: String {
        switch self {
        case .unicodeInput: return "unicodeApps.addFailed.message"
        case .exclusions: return "exclusions.addFailed.message"
        }
    }

    var icon: String {
        switch self {
        case .unicodeInput: return "keyboard.badge.ellipsis"
        case .exclusions: return "nosign.app"
        }
    }

    var emptyIcon: String {
        switch self {
        case .unicodeInput: return "keyboard"
        case .exclusions: return "checkmark.circle"
        }
    }

    var notificationName: Notification.Name {
        switch self {
        case .unicodeInput: return .textFlashUnicodeAppsDidChange
        case .exclusions: return .textFlashExclusionsDidChange
        }
    }

    var bundleIDs: Set<String> {
        switch self {
        case .unicodeInput: return EventController.shared.unicodeBundleIDs
        case .exclusions: return EventController.shared.excludedBundleIDs
        }
    }

    func setBundleIDs(_ bundleIDs: Set<String>) {
        switch self {
        case .unicodeInput:
            EventController.shared.unicodeBundleIDs = bundleIDs
        case .exclusions:
            EventController.shared.excludedBundleIDs = bundleIDs
        }
    }
}

private struct SheetDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(SettingsPalette.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct SettingsSection<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    init(
        icon: String,
        title: String,
        subtitle: String,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let action {
                Button(action: action) {
                    labelContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                labelContent
            }

            Spacer(minLength: 16)
            accessory
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(SettingsPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.border))
    }

    private var labelContent: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(SettingsPalette.accent)
                .frame(width: 30, height: 30)
                .background(SettingsPalette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SettingsPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsPalette {
    static let window = SoftTheme.window
    static let glass = SoftTheme.glass
    static let field = SoftTheme.field
    static let border = SoftTheme.border
    static let accent = SoftTheme.accent
    static let warning = SoftTheme.warning
    static let success = SoftTheme.success
    static let primaryText = SoftTheme.primaryText
    static let secondaryText = SoftTheme.secondaryText
    static let mutedText = SoftTheme.mutedText
}

private extension View {
    func glassContainer(cornerRadius: CGFloat) -> some View {
        self
            .background(SettingsPalette.glass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(SettingsPalette.border))
            .shadow(color: SoftTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

private struct SummaryPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SettingsPalette.mutedText)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SettingsPalette.border))
    }
}

#if !DISABLE_PREVIEWS
#Preview {
    SettingsView()
}
#endif
