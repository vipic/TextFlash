import SwiftUI

enum UpdateState {
    case upToDate(version: String, build: String, lastCheckDate: Date?, lastReleaseNotes: String?)
    case updateAvailable(result: UpdateChecker.UpdateResult)
    case checking
    case downloading(progress: Double)
    case installing
    case error(String)
}

struct UpdateView: View {
    @ObservedObject private var settings = AppSettings.shared
    let state: UpdateState
    let releaseNotes: String?
    let currentVersion: String?
    let latestVersion: String?
    var onUpdate: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            SoftTheme.window
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                    .updateGlass(cornerRadius: 18)

                if let releaseNotes, !releaseNotes.isEmpty {
                    changelogSection(releaseNotes)
                }

                if case .downloading = state {
                    progressCard
                }

                buttonRow
            }
            .padding(18)
        }
        .frame(width: 460)
        .frame(minHeight: 340, maxHeight: .infinity)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                statusIcon

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SoftTheme.primaryText)
                        .lineLimit(2)

                    versionRow

                    if case .upToDate(_, _, let lastCheck, _) = state, let date = lastCheck {
                        lastCheckedRow(date)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(statusTint.opacity(0.12))
                .frame(width: 52, height: 52)

            switch state {
            case .checking:
                ProgressView()
                    .scaleEffect(0.72)
                    .frame(width: 24, height: 24)
            default:
                Image(systemName: statusSymbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(statusTint)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(statusTint.opacity(0.16)))
    }

    private var title: String {
        switch state {
        case .upToDate:
            return L10n.t("update.upToDate")
        case .updateAvailable, .downloading, .installing:
            return L10n.t("update.available")
        case .checking:
            return L10n.t("update.checking")
        case .error:
            return L10n.t("update.failed")
        }
    }

    private var statusSymbol: String {
        switch state {
        case .upToDate:
            return "checkmark"
        case .updateAvailable:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down"
        case .installing:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle"
        case .checking:
            return "arrow.clockwise"
        }
    }

    private var statusTint: Color {
        switch state {
        case .upToDate:
            return SoftTheme.success
        case .updateAvailable, .downloading, .installing:
            return SoftTheme.accent
        case .error:
            return SoftTheme.warning
        case .checking:
            return SoftTheme.secondaryText
        }
    }

    private func lastCheckedRow(_ date: Date) -> some View {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppSettings.shared.language == .zhHans ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")
        let relative = abs(Date().timeIntervalSince(date)) < 3
            ? L10n.t("update.justNow")
            : formatter.localizedString(for: date, relativeTo: Date())

        return Text(String(format: L10n.t("update.lastChecked"), relative))
            .font(.system(size: 12))
            .foregroundColor(SoftTheme.mutedText)
    }

    @ViewBuilder
    private var versionRow: some View {
        switch state {
        case .upToDate(let version, let build, _, _):
            Text("\(L10n.t("update.current")) v\(UpdateChecker.displayVersion(version)) · Build \(build)")
                .font(.system(size: 13))
                .foregroundColor(SoftTheme.secondaryText)
        case .updateAvailable(let result):
            versionTransition(current: result.currentVersion, latest: result.latestVersion)
        case .checking:
            Text(L10n.t("update.title"))
                .font(.system(size: 13))
                .foregroundColor(SoftTheme.secondaryText)
        case .downloading:
            if let currentVersion, let latestVersion {
                versionTransition(current: currentVersion, latest: latestVersion)
            }
        case .installing:
            Text(L10n.t("update.installingMessage"))
                .font(.system(size: 13))
                .foregroundColor(SoftTheme.secondaryText)
        case .error(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(SoftTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func versionTransition(current: String, latest: String) -> some View {
        HStack(spacing: 7) {
            Text("\(L10n.t("update.current")) v\(UpdateChecker.displayVersion(current))")
                .foregroundColor(SoftTheme.secondaryText)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(SoftTheme.mutedText)
            Text("\(L10n.t("update.latest")) v\(UpdateChecker.displayVersion(latest))")
                .fontWeight(.semibold)
                .foregroundColor(SoftTheme.primaryText)
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }

    private func changelogSection(_ notes: String) -> some View {
        let items = parseChangelog(notes)

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("update.whatsNew"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SoftTheme.mutedText)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(SoftTheme.accent)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundColor(SoftTheme.secondaryText)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(SoftTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SoftTheme.border))
            }
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        switch state {
        case .upToDate:
            HStack {
                Spacer()
                UpdateActionButton(title: L10n.t("update.ok"), prominent: true) { onCancel?() }
            }
        case .updateAvailable:
            HStack(spacing: 8) {
                Spacer()
                UpdateActionButton(title: L10n.t("update.cancel"), prominent: false) { onCancel?() }
                UpdateActionButton(title: L10n.t("update.updateButton"), prominent: true) { onUpdate?() }
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading:
            HStack {
                Spacer()
                UpdateActionButton(title: L10n.t("update.cancel"), prominent: false) { onCancel?() }
            }
        case .installing, .checking:
            EmptyView()
        case .error:
            HStack {
                Spacer()
                UpdateActionButton(title: L10n.t("update.ok"), prominent: true) { onCancel?() }
            }
        }
    }

    private var progressCard: some View {
        VStack(spacing: 10) {
            progressBar
            Text(L10n.t("update.downloading"))
                .font(.system(size: 12))
                .foregroundColor(SoftTheme.secondaryText)
        }
        .padding(14)
        .background(SoftTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SoftTheme.border))
    }

    private var progressBar: some View {
        VStack(spacing: 7) {
            if case .downloading(let progress) = state {
                let clampedProgress = min(max(progress, 0), 1)
                let visibleProgress = max(clampedProgress, 0.02)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SoftTheme.accentSoft)
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SoftTheme.accent)
                            .frame(width: geo.size.width * CGFloat(visibleProgress), height: 7)
                    }
                }
                .frame(height: 7)

                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SoftTheme.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    private func parseChangelog(_ body: String) -> [String] {
        body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("*") }
            .map { line -> String in
                guard let index = line.firstIndex(where: { $0 != "-" && $0 != "*" && $0 != " " }) else {
                    return ""
                }
                return String(line[index...]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}

private struct UpdateActionButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(prominent ? .white : SoftTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(prominent ? SoftTheme.accent : SoftTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? Color.clear : SoftTheme.border))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func updateGlass(cornerRadius: CGFloat) -> some View {
        background(SoftTheme.glass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(SoftTheme.border))
            .shadow(color: SoftTheme.shadow, radius: 18, x: 0, y: 10)
    }
}
