import SwiftUI

struct AboutView: View {
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
            Text(String(format: L10n.t("about.version"), versionString, buildString))
                .font(.system(size: 12))
                .foregroundColor(.secondary)

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
}

#if !DISABLE_PREVIEWS
#Preview {
    AboutView()
}
#endif
