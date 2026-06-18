import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            SoftTheme.window
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                    .aboutGlass(cornerRadius: 18)

                HStack(spacing: 10) {
                    AboutInfoTile(label: L10n.t("about.version"), value: versionString)
                    AboutInfoTile(label: L10n.t("about.build"), value: buildString)
                }

                Text(L10n.t("about.description"))
                    .font(.system(size: 13))
                    .foregroundColor(SoftTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)

                Text(L10n.t("about.credits"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SoftTheme.mutedText)
                    .padding(.top, 2)
            }
            .padding(18)
        }
        .frame(width: 360, height: 300)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: SoftTheme.shadow, radius: 14, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(SoftTheme.primaryText)

                Text(L10n.t("about.title"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SoftTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
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

private struct AboutInfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(SoftTheme.mutedText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SoftTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(SoftTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SoftTheme.border))
    }
}

private extension View {
    func aboutGlass(cornerRadius: CGFloat) -> some View {
        background(SoftTheme.glass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(SoftTheme.border))
            .shadow(color: SoftTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

#if !DISABLE_PREVIEWS
#Preview {
    AboutView()
}
#endif
