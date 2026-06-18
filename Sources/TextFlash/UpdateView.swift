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
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, 30)
                .padding(.bottom, 14)

            headingRow
                .padding(.bottom, 4)

            versionRow
                .padding(.bottom, 8)

            if case .upToDate(_, _, let lastCheck, _) = state, let date = lastCheck {
                lastCheckedRow(date)
                    .padding(.bottom, 16)
            } else {
                Color.clear.frame(height: 0)
                    .padding(.bottom, 16)
            }

            if let releaseNotes, !releaseNotes.isEmpty {
                changelogSection(releaseNotes)
                    .padding(.bottom, 24)
            }

            buttonRow
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 28)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var headingRow: some View {
        HStack(spacing: 8) {
            switch state {
            case .upToDate:
                Text(L10n.t("update.upToDate"))
                    .font(.system(size: 17, weight: .semibold))
                ZStack {
                    Circle()
                        .fill(Color(red: 0.188, green: 0.82, blue: 0.345))
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            case .updateAvailable, .downloading, .installing:
                Text(L10n.t("update.available"))
                    .font(.system(size: 17, weight: .semibold))
                Circle()
                    .fill(Color(red: 0.188, green: 0.82, blue: 0.345))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(red: 0.188, green: 0.82, blue: 0.345).opacity(0.5), radius: 6)
            case .checking:
                Text(L10n.t("update.checking"))
                    .font(.system(size: 17, weight: .semibold))
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 18, height: 18)
            case .error:
                Text(L10n.t("update.failed"))
                    .font(.system(size: 17, weight: .semibold))
            }
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
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var versionRow: some View {
        switch state {
        case .upToDate(let version, let build, _, _):
            Text("\(L10n.t("update.current")) v\(UpdateChecker.displayVersion(version)) · Build \(build)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        case .updateAvailable(let result):
            versionTransition(current: result.currentVersion, latest: result.latestVersion)
        case .checking:
            EmptyView()
        case .downloading:
            if let currentVersion, let latestVersion {
                versionTransition(current: currentVersion, latest: latestVersion)
            } else {
                EmptyView()
            }
        case .installing:
            Text(L10n.t("update.installingMessage"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        case .error(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private func versionTransition(current: String, latest: String) -> some View {
        HStack(spacing: 6) {
            Text("\(L10n.t("update.current")) v\(UpdateChecker.displayVersion(current))")
                .foregroundColor(.secondary)
            Text("->")
                .foregroundColor(.secondary.opacity(0.5))
            Text("\(L10n.t("update.latest")) v\(UpdateChecker.displayVersion(latest))")
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
    }

    private func changelogSection(_ notes: String) -> some View {
        let items = parseChangelog(notes)

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("update.whatsNew"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(item)
                                    .font(.system(size: 13))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        switch state {
        case .upToDate:
            HStack {
                Spacer()
                Button(L10n.t("update.ok")) { onCancel?() }
            }
        case .updateAvailable:
            HStack(spacing: 10) {
                Spacer()
                Button(L10n.t("update.cancel")) { onCancel?() }
                Button(L10n.t("update.updateButton")) { onUpdate?() }
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading:
            VStack(spacing: 10) {
                progressBar
                Text(L10n.t("update.downloading"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button(L10n.t("update.cancel")) { onCancel?() }
                }
            }
        case .installing, .checking:
            EmptyView()
        case .error:
            HStack {
                Spacer()
                Button(L10n.t("update.ok")) { onCancel?() }
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            if case .downloading(let progress) = state {
                let clampedProgress = min(max(progress, 0), 1)
                let visibleProgress = max(clampedProgress, 0.02)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(visibleProgress), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
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
