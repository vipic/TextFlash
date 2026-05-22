import SwiftUI
import Combine

/// 调试面板 —— 实时显示 EventController 内部状态，帮助诊断展开问题
struct DebugPanel: View {
    @State private var buffer = ""
    @State private var isRunning = false
    @State private var isInjecting = false
    @State private var snippetCount = 0
    @State private var exclusionCount = 0
    @State private var tapRecoveryCount = 0
    @State private var snippetList: [String] = []
    @State private var logLines: [String] = []

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let logURL = URL(fileURLWithPath: "/tmp/textflash_events.log")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 状态行
            HStack(spacing: 16) {
                statusBadge(label: "Event Tap", ok: isRunning)
                statusBadge(label: "注入中", ok: !isInjecting, okText: "闲置", failText: "注入中")
            }

            // Buffer 显示
            HStack {
                Text("Buffer:")
                    .font(.headline)
                Text(buffer.isEmpty ? "(空)" : "\"\(buffer)\"")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(buffer.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }

            // 已加载缩写
            Text("已加载 \(snippetCount) 条缩写")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("排除 \(exclusionCount) 个应用 · Tap 恢复 \(tapRecoveryCount) 次")
                .font(.caption)
                .foregroundColor(.secondary)

            if !snippetList.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snippetList, id: \.self) { item in
                            Text(item)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(maxHeight: 100)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
            }

            Divider()

            // 事件日志
            Text("事件日志")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(logLineColor(line))
                        }
                    }
                    .onChange(of: logLines.count) { _ in
                        proxy.scrollTo(logLines.count - 1, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 200)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
        }
        .padding()
        .frame(width: 480, height: 420)
        .onReceive(timer) { _ in
            refresh()
        }
    }

    private func statusBadge(label: String, ok: Bool, okText: String = "运行", failText: String = "停止") -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text("\(label): \(ok ? okText : failText)")
                .font(.caption)
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
