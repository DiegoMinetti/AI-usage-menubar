import SwiftUI
import WidgetKit

struct AIUsageTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct AIUsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIUsageTimelineEntry {
        AIUsageTimelineEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (AIUsageTimelineEntry) -> Void) {
        completion(AIUsageTimelineEntry(date: Date(), snapshot: UsageSnapshotStore.load() ?? previewSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIUsageTimelineEntry>) -> Void) {
        let now = Date()
        let entry = AIUsageTimelineEntry(date: now, snapshot: UsageSnapshotStore.load() ?? UsageSnapshot.empty)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var previewSnapshot: UsageSnapshot {
        UsageSnapshot(
            generatedAt: Date(),
            services: [
                .init(id: "claude", name: "Claude Code", detail: "28.4K last 7d", usedLabel: "42% session", percentage: 42, status: "Connected", tintHex: "#DA7756", resetLabel: "Resets in 2h 10m"),
                .init(id: "copilot", name: "GitHub Copilot", detail: "73.5% available", usedLabel: "26.5% used", percentage: 26.5, status: "Connected", tintHex: "#8534F3", resetLabel: "Resets in 12d"),
                .init(id: "codex", name: "ChatGPT / Codex", detail: "5 active threads", usedLabel: "186.7K last 7d", percentage: nil, status: "gpt-5.5", tintHex: "#10A37F", resetLabel: "Updated now")
            ]
        )
    }
}

struct AIUsageWidgetView: View {
    let entry: AIUsageTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI Usage")
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold))
                Spacer()
                Text(entry.snapshot.generatedAt, style: .time)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.services.isEmpty {
                Spacer(minLength: 0)
                Text("Open AI Usage once to publish local usage data.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ForEach(visibleServices) { service in
                    WidgetServiceView(service: service, compact: family == .systemSmall)
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var visibleServices: [UsageSnapshot.Service] {
        if family == .systemSmall {
            if let codex = entry.snapshot.services.first(where: { $0.id == "codex" }) {
                return [codex]
            }
            return Array(entry.snapshot.services.prefix(1))
        }
        return entry.snapshot.services
    }
}

private struct WidgetServiceView: View {
    let service: UsageSnapshot.Service
    let compact: Bool

    var body: some View {
        if compact, service.id == "codex", service.status == "Usage" {
            CodexCompactWidgetView(service: service, tint: tint)
        } else {
            serviceBody
        }
    }

    private var serviceBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.name)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(service.usedLabel)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            ProgressView(value: min(max((service.percentage ?? 0) / 100, 0), 1))
                .tint(tint)

            if !compact {
                HStack {
                    Text(service.detail)
                    Spacer(minLength: 6)
                    Text(service.resetLabel ?? service.status)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        Color(hex: service.tintHex) ?? .accentColor
    }
}

private struct CodexCompactWidgetView: View {
    let service: UsageSnapshot.Service
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 6)
                Text(service.usedLabel)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            ForEach(limitRows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(row.value)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(max((service.percentage ?? 0) / 100, 0), 1))
                .tint(tint)

            if let resetLabel = service.resetLabel {
                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var limitRows: [LimitRow] {
        let rows = service.detail
            .split(separator: "·")
            .compactMap { LimitRow(rawValue: String($0)) }
        return rows.isEmpty ? [LimitRow(label: "5 h", value: service.usedLabel)] : rows
    }

    private struct LimitRow {
        let label: String
        let value: String

        init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        init?(rawValue: String) {
            let parts = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            guard parts.count >= 2 else { return nil }
            let rawLabel = parts.dropLast().joined(separator: " ")
            label = Self.displayLabel(for: rawLabel)
            value = String(parts.last ?? "")
        }

        private static func displayLabel(for rawLabel: String) -> String {
            switch rawLabel.lowercased() {
            case "5h": return "5 h"
            case "weekly": return "Semanal"
            case "monthly": return "Mensual"
            default: return rawLabel
            }
        }
    }
}

@main
struct AIUsageWidget: Widget {
    let kind = "AIUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIUsageTimelineProvider()) { entry in
            AIUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Claude, Copilot, and ChatGPT/Codex usage from local app data.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
