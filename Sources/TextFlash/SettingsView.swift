import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var hasAccessibilityPermission = EventController.shared.checkPermission()
    @State private var launchAtLogin = LoginItemController.isEnabled
    @State private var settingsErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                languageSection
                launchSection
                timingSection
                permissionSection
                exclusionSection
            }
            .padding(20)
        }
        .frame(width: 540)
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
                Label(L10n.t("settings.permission.button"), systemImage: "lock.open")
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

    private var exclusionSection: some View {
        SettingsSection(
            icon: "nosign.app",
            title: L10n.t("settings.exclusions.title"),
            subtitle: L10n.t("settings.exclusions.subtitle")
        ) {
            Text("\(EventController.shared.excludedBundleIDs.count)")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
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
