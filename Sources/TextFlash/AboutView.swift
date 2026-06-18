import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // 应用图标
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Spacer().frame(height: 20)

            // 应用名称
            Text(appName)
                .font(.system(size: 18, weight: .bold))

            Spacer().frame(height: 6)

            // 版本信息
            HStack(spacing: 10) {
                versionRow(label: L10n.t("about.version"), value: versionString)
                versionRow(label: L10n.t("about.build"), value: buildString)
            }

            Spacer().frame(height: 16)

            // 描述
            Text(L10n.t("about.description"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260)

            Spacer().frame(height: 24)

            Divider()
                .frame(width: 260)

            Spacer().frame(height: 16)

            // 致谢
            Text(L10n.t("about.credits"))
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(30)
        .frame(width: 320)
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
        .foregroundColor(.secondary)
    }
}

#if !DISABLE_PREVIEWS
#Preview {
    AboutView()
}
#endif
