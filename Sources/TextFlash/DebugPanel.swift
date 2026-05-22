import SwiftUI
import Combine

/// 调试面板 —— 实时显示 EventController 内部状态，帮助诊断展开问题
struct DebugPanel: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var buffer = ""
    @State private var isRunning = false
    @State private var isInjecting = false
    @State private var hasAccessibilityPermission = false
    @State private var snippetCount = 0
    @State private var exclusionCount = 0
    @State private var tapRecoveryCount = 0
    @State private var snippetList: [String] = []
    @State private var logLines: [String] = []

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let logURL = URL(fileURLWithPath: "/tmp/textflash_events.log")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                statusCard(
                    title: L10n.t("debug.eventTap"),
                    value: isRunning ? L10n.t("debug.running") : L10n.t("debug.stopped"),
                    systemImage: isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    tint: isRunning ? .green : .red
                )
                statusCard(
                    title: L10n.t("debug.accessibility"),
                    value: hasAccessibilityPermission ? L10n.t("debug.enabled") : L10n.t("debug.disabled"),
                    systemImage: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: hasAccessibilityPermission ? .green : .orange
                )
                statusCard(
                    title: L10n.t("debug.injection"),
                    value: isInjecting ? L10n.t("debug.injecting") : L10n.t("debug.idle"),
                    systemImage: isInjecting ? "keyboard.badge.ellipsis" : "keyboard",
                    tint: isInjecting ? .blue : .secondary
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    metric(label: L10n.t("debug.loadedSnippets"), value: "\(snippetCount)")
                    metric(label: L10n.t("debug.exclusions"), value: "\(exclusionCount)")
                    metric(label: L10n.t("debug.tapRecoveries"), value: "\(tapRecoveryCount)")
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("debug.buffer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(buffer.isEmpty ? L10n.t("debug.empty") : buffer)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(buffer.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))

            HStack(alignment: .top, spacing: 12) {
                logPanel(
                    title: L10n.t("debug.abbreviations"),
                    emptyText: L10n.t("debug.empty"),
                    lines: snippetList,
                    maxHeight: .infinity
                ) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                logPanel(
                    title: L10n.t("debug.eventLog"),
                    emptyText: L10n.t("debug.noLog"),
                    lines: logLines,
                    maxHeight: .infinity
                ) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(logLineColor(line))
                        .lineLimit(1)
                }
            }
        }
        .padding(18)
        .frame(width: 560, height: 520)
        .onReceive(timer) { _ in
            refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("debug.title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.t("debug.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func statusCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(tint)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 82, alignment: .leading)
    }

    private func logPanel<Content: View>(
        title: String,
        emptyText: String,
        lines: [String],
        maxHeight: CGFloat,
        @ViewBuilder row: @escaping (String) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 3) {
                        if lines.isEmpty {
                            Text(emptyText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                row(line)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: lines.count) { _ in
                        guard !lines.isEmpty else { return }
                        proxy.scrollTo(lines.count - 1, anchor: .bottom)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("blocked") { return .orange }
        if line.contains("reset") { return .secondary }
        if line.contains("TRIG") { return .blue }
        if line.contains("BUF trigger") { return .green }
        return .primary
    }

    private func refresh() {
        let ec = EventController.shared
        buffer = ec.inputBuffer
        isRunning = ec.isRunning
        isInjecting = ec.isInjecting
        hasAccessibilityPermission = ec.checkPermission()
        exclusionCount = ec.excludedBundleIDs.count
        tapRecoveryCount = ec.tapRecoveryCount

        // 读取缩写列表
        let abbrs = ec.loadedAbbreviations
        snippetCount = abbrs.count
        snippetList = abbrs.sorted().map { "  \($0) → \(ec.expansionFor($0) ?? "?")" }

        // 读取日志（最后 30 行）
        if let content = try? String(contentsOf: logURL, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            logLines = Array(lines.suffix(30))
        }
    }
}
