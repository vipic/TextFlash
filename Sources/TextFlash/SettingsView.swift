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
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                languageSection
                launchSection
                timingSection
                unicodeAppsSection
                permissionSection
                exclusionSection
            }
            .padding(20)
        }
        .frame(width: 540)
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
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("settings.title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.t("settings.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var languageSection: some View {
        SettingsSection(
            icon: "globe",
            title: L10n.t("settings.language.title"),
            subtitle: L10n.t("settings.language.subtitle")
        ) {
            Picker("", selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
    }

    private var permissionSection: some View {
        SettingsSection(
            icon: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
            title: L10n.t("settings.permission.title"),
            subtitle: hasAccessibilityPermission
                ? L10n.t("settings.permission.enabled")
                : L10n.t("settings.permission.disabled")
        ) {
            Button {
                EventController.shared.requestPermission()
                hasAccessibilityPermission = EventController.shared.checkPermission()
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
            subtitle: L10n.t("settings.unicodeApps.subtitle")
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
            subtitle: L10n.t("settings.exclusions.subtitle")
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
        }
    }
}

private struct UnicodeAppsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var bundleIDs = Array(EventController.shared.unicodeBundleIDs).sorted()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("unicodeApps.title"))
                    .font(.headline)
                Spacer()
                Button {
                    addCurrentApplication()
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.plain)
                .help(L10n.t("unicodeApps.addCurrent"))

                Button {
                    chooseApplication()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(L10n.t("unicodeApps.choose"))

                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(bundleIDs.isEmpty)
                .help(L10n.t("unicodeApps.clear"))

                Button(L10n.t("common.done")) {
                    dismiss()
                }
            }
            .padding()

            Divider()

            if bundleIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L10n.t("unicodeApps.empty"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appName(for: bundleID))
                                    .font(.body)
                                Text(bundleID)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                remove(bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("unicodeApps.remove"))
                        }
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 340)
        .onReceive(NotificationCenter.default.publisher(for: .textFlashUnicodeAppsDidChange)) { _ in
            refresh()
        }
        .alert(L10n.t("unicodeApps.addFailed.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("unicodeApps.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK else { return }
        var values = EventController.shared.unicodeBundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                values.insert(bundleID)
            }
        }
        EventController.shared.unicodeBundleIDs = values
        refresh()
    }

    private func addCurrentApplication() {
        guard let app = EventController.shared.exclusionTargetApplication() else {
            errorMessage = L10n.t("unicodeApps.addFailed.message")
            return
        }
        var values = EventController.shared.unicodeBundleIDs
        values.insert(app.bundleID)
        EventController.shared.unicodeBundleIDs = values
        refresh()
    }

    private func remove(_ bundleID: String) {
        var values = EventController.shared.unicodeBundleIDs
        values.remove(bundleID)
        EventController.shared.unicodeBundleIDs = values
        refresh()
    }

    private func clearAll() {
        EventController.shared.unicodeBundleIDs = []
        refresh()
    }

    private func refresh() {
        bundleIDs = Array(EventController.shared.unicodeBundleIDs).sorted()
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
}

private struct ExcludedAppsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var bundleIDs = Array(EventController.shared.excludedBundleIDs).sorted()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("exclusions.title"))
                    .font(.headline)
                Spacer()
                Button {
                    addCurrentApplication()
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.plain)
                .help(L10n.t("exclusions.addCurrent"))

                Button {
                    chooseApplication()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(L10n.t("exclusions.choose"))

                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(bundleIDs.isEmpty)
                .help(L10n.t("exclusions.clear"))

                Button(L10n.t("common.done")) {
                    dismiss()
                }
            }
            .padding()

            Divider()

            if bundleIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L10n.t("exclusions.empty"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appName(for: bundleID))
                                    .font(.body)
                                Text(bundleID)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                remove(bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("exclusions.remove"))
                        }
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 340)
        .onReceive(NotificationCenter.default.publisher(for: .textFlashExclusionsDidChange)) { _ in
            refresh()
        }
        .alert(L10n.t("exclusions.addFailed.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("exclusions.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK else { return }
        var values = EventController.shared.excludedBundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                values.insert(bundleID)
            }
        }
        EventController.shared.excludedBundleIDs = values
        refresh()
    }

    private func addCurrentApplication() {
        guard let app = EventController.shared.exclusionTargetApplication() else {
            errorMessage = L10n.t("exclusions.addFailed.message")
            return
        }
        var values = EventController.shared.excludedBundleIDs
        values.insert(app.bundleID)
        EventController.shared.excludedBundleIDs = values
        refresh()
    }

    private func remove(_ bundleID: String) {
        var values = EventController.shared.excludedBundleIDs
        values.remove(bundleID)
        EventController.shared.excludedBundleIDs = values
        refresh()
    }

    private func clearAll() {
        EventController.shared.excludedBundleIDs = []
        refresh()
    }

    private func refresh() {
        bundleIDs = Array(EventController.shared.excludedBundleIDs).sorted()
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
}

private struct SettingsSection<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
            accessory
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

#if !DISABLE_PREVIEWS
#Preview {
    SettingsView()
}
#endif
