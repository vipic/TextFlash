import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            SoftTheme.window
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 20)

                Text(appName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SoftTheme.primaryText)

                Spacer().frame(height: 6)

                HStack(spacing: 10) {
                    versionRow(label: L10n.t("about.version"), value: versionString)
                    versionRow(label: L10n.t("about.build"), value: buildString)
                }

                Spacer().frame(height: 16)

                Text(L10n.t("about.description"))
                    .font(.system(size: 12))
                    .foregroundColor(SoftTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260)

                Spacer().frame(height: 24)

                Divider()
                    .overlay(SoftTheme.border)
                    .frame(width: 260)

                Spacer().frame(height: 16)

                Text(L10n.t("about.credits"))
                    .font(.system(size: 10))
                    .foregroundColor(SoftTheme.mutedText)
            }
            .padding(30)
        }
        .frame(width: 320)
        .preferredColorScheme(.light)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "TextFlash"
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private func versionRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .fontWeight(.medium)
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundColor(SoftTheme.secondaryText)
    }
}

#if !DISABLE_PREVIEWS
#Preview {
    AboutView()
}
#endif
