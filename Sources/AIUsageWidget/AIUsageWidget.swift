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

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "ai-usage://charts"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot.services.isEmpty {
            Spacer(minLength: 0)
            Text("Open AI Usage once to publish local usage data.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        } else {
            switch family {
            case .systemSmall:
                serviceColumn(visibleServices, density: .compact)
            case .systemMedium:
                HStack(alignment: .top, spacing: 8) {
                    ForEach(visibleServices) { service in
                        WidgetServiceView(service: service, density: .regular)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            case .systemLarge:
                largeServiceSlots(visibleServices)
            default:
                serviceColumn(visibleServices, density: .regular)
            }
        }
    }

    private func serviceColumn(_ services: [UsageSnapshot.Service], density: WidgetServiceDensity) -> some View {
        VStack(alignment: .leading, spacing: density.spacing) {
            ForEach(services) { service in
                WidgetServiceView(service: service, density: density)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func largeServiceSlots(_ services: [UsageSnapshot.Service]) -> some View {
        let slotCount = services.count <= 1 ? 1 : (services.count == 2 ? 2 : 4)

        return VStack(alignment: .leading, spacing: WidgetServiceDensity.expanded.spacing) {
            ForEach(0..<slotCount, id: \.self) { index in
                if services.indices.contains(index) {
                    WidgetServiceView(service: services[index], density: .expanded)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var visibleServices: [UsageSnapshot.Service] {
        switch family {
        case .systemSmall:
            return Array(entry.snapshot.services.prefix(1))
        case .systemMedium:
            return Array(entry.snapshot.services.prefix(2))
        case .systemLarge:
            let limit = entry.snapshot.services.count > 2 ? 4 : 2
            return Array(entry.snapshot.services.prefix(limit))
        default:
            return entry.snapshot.services
        }
    }
}

private enum WidgetServiceDensity {
    case compact
    case regular
    case expanded

    var spacing: CGFloat {
        switch self {
        case .compact: 6
        case .regular: 8
        case .expanded: 7
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 11
        case .expanded: 12
        }
    }

    var metaSize: CGFloat {
        switch self {
        case .compact: 9
        case .regular: 9
        case .expanded: 10
        }
    }

    var pointLimit: Int {
        switch self {
        case .compact: 18
        case .regular: 22
        case .expanded: 32
        }
    }

    var minChartHeight: CGFloat {
        switch self {
        case .compact: 42
        case .regular: 44
        case .expanded: 38
        }
    }
}

private struct WidgetServiceView: View {
    let service: UsageSnapshot.Service
    let density: WidgetServiceDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.name)
                    .font(.system(size: density.titleSize, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(service.usedLabel)
                    .font(.system(size: density.titleSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            SnapshotMiniChart(
                points: service.chartPoints,
                tint: tint,
                fallbackProgress: min(max((service.percentage ?? 0) / 100, 0), 1),
                pointLimit: density.pointLimit
            )
            .frame(minHeight: density.minChartHeight, maxHeight: .infinity)
            .layoutPriority(1)

            if density != .compact {
                HStack {
                    Text(service.detail)
                    Spacer(minLength: 6)
                    Text(service.resetLabel ?? service.status)
                }
                .font(.system(size: density.metaSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tint: Color {
        Color(hex: service.tintHex) ?? .accentColor
    }
}

private struct SnapshotMiniChart: View {
    let points: [UsageSnapshot.ChartPoint]
    let tint: Color
    let fallbackProgress: Double
    let pointLimit: Int

    var body: some View {
        GeometryReader { proxy in
            let visiblePoints = Array(points.suffix(pointLimit))
            let maxValue = max(visiblePoints.map(\.value).max() ?? 0, 1)
            let chartHeight = max(proxy.size.height - 6, 4)

            HStack(alignment: .bottom, spacing: pointLimit > 24 ? 2 : 3) {
                if visiblePoints.isEmpty {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(height: max(CGFloat(fallbackProgress) * chartHeight, fallbackProgress > 0 ? 3 : 2))
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(visiblePoints) { point in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(point.projected ? tint.opacity(0.28) : tint.opacity(point.value > 0 ? 0.86 : 0.16))
                            .frame(height: max(CGFloat(point.value / maxValue) * chartHeight, point.value > 0 ? 3 : 2))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.secondary.opacity(0.08))
            )
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
