import SwiftUI

// MARK: - Root view

struct MenuContentView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        VStack(spacing: 0) {
            ClaudeSectionView(vm: vm)
            Divider().opacity(0.3)
            CopilotSectionView(vm: vm)
        }
        .frame(width: 290)
        .background(Color.clear)
    }
}

// MARK: - Claude section

private struct ClaudeSectionView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "CLAUDE CODE",
                dotColor: vm.claudeStatus.dotColor,
                statusLabel: vm.claudeStatus.label
            )

            switch vm.claudeStatus {
            case .notInstalled:
                Text("Claude CLI not installed.\nInstall it at claude.ai/code to start tracking.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .notAuthenticated:
                Text("Claude CLI detected but not authenticated.\nRun `claude` to sign in.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .connected:
                SessionRowView(usage: vm.claudeUsage)
                Divider().opacity(0.2)
                WeeklyRowView(usage: vm.claudeUsage)
                Divider().opacity(0.2)
                ClaudeMonthlyChart(usage: vm.claudeUsage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Session row (5h window)

private struct SessionRowView: View {
    let usage: ClaudeUsage

    private let windowDuration: TimeInterval = 5 * 3600

    /// Fraction of the 5h window already elapsed (0 → 1).
    private var elapsedFraction: Double {
        guard let remaining = usage.timeRemainingInSession else { return 0 }
        let elapsed = windowDuration - min(remaining, windowDuration)
        return elapsed / windowDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Session  · 5h window")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                if usage.isInActiveSession {
                    Text(formatTokens(usage.sessionTokens))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }

            if usage.isInActiveSession {
                // Bar = time elapsed inside the 5h window
                UsageBar(value: elapsedFraction, color: sessionBarColor(elapsedFraction))

                HStack {
                    // How long ago the session started
                    let elapsed = windowDuration * elapsedFraction
                    Text("Started \(formatDuration(elapsed)) ago")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    // Time remaining until window closes
                    if let remaining = usage.timeRemainingInSession {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("resets in \(formatDuration(remaining))")
                                .font(.system(size: 10).monospacedDigit())
                        }
                        .foregroundColor(resetColor(remaining))
                    }
                }
            } else {
                Text("No activity in the last 5h")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                UsageBar(value: 0, color: .accentColor)
            }
        }
    }

    private func sessionBarColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .accentColor
        case ..<0.85: return .orange
        default: return .red
        }
    }

    private func resetColor(_ remaining: TimeInterval) -> Color {
        if remaining < 1800 { return .red }       // < 30 min
        if remaining < 3600 { return .orange }    // < 1h
        return .secondary
    }
}

// MARK: - Weekly row

private struct WeeklyRowView: View {
    let usage: ClaudeUsage

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer()
            Text(formatTokens(usage.weeklyTokens))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }
}

// MARK: - Claude monthly chart

private struct ClaudeMonthlyChart: View {
    let usage: ClaudeUsage

    var body: some View {
        let (actual, projected, limitY) = buildChartData()

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("This month")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if usage.hasUsageData {
                    Text(formatTokens(usage.totalTokens))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                } else {
                    Text("Simulated")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            CumulativeLineChart(
                actualPoints: actual,
                projectedPoints: projected,
                referenceY: limitY,
                color: usage.hasUsageData ? .accentColor : Color.accentColor.opacity(0.4)
            )
            .frame(height: 52)

            if usage.hasUsageData && usage.dailyAverage > 0 {
                HStack {
                    Text("~\(formatTokens(Int(usage.dailyAverage)))/day avg")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    let proj = usage.projectedMonthlyTokens
                    Text("Proj. \(formatTokens(proj))")
                        .font(.system(size: 10))
                        .foregroundColor(proj > usage.monthlyLimit ? .orange : .secondary)
                }
            } else if !usage.hasUsageData {
                Text("No usage data recorded yet.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buildChartData() -> (actual: [(CGFloat, CGFloat)], projected: [(CGFloat, CGFloat)], limitY: CGFloat) {
        let history = usage.dailyHistory
        guard usage.hasUsageData else {
            let n = 30
            var sim: [(CGFloat, CGFloat)] = []
            for i in 0..<n {
                sim.append((CGFloat(i) / CGFloat(max(n - 1, 1)), CGFloat(i + 1) / CGFloat(n)))
            }
            return ([], sim, 1.0)
        }

        let projectedEnd = max(usage.projectedMonthlyTokens, usage.totalTokens)
        let limit  = max(usage.monthlyLimit, 1)
        let yMax   = max(Double(limit), Double(projectedEnd)) * 1.05
        let todayStr = ymdToday()
        let todayIdx = history.firstIndex(where: { $0.date == todayStr }) ?? (history.count - 1)
        let n = history.count

        var cum = 0
        var actual: [(CGFloat, CGFloat)] = []
        for (i, day) in history.enumerated() {
            cum += day.tokens
            if i <= todayIdx {
                actual.append((CGFloat(i) / CGFloat(max(n - 1, 1)), CGFloat(cum) / CGFloat(yMax)))
            }
        }

        var projected: [(CGFloat, CGFloat)] = []
        if let last = actual.last {
            projected.append(last)
            var projCum = Double(cum)
            let remaining = n - 1 - todayIdx
            if remaining > 0 {
                for j in 1...remaining {
                    projCum += usage.dailyAverage
                    let x = CGFloat(todayIdx + j) / CGFloat(max(n - 1, 1))
                    projected.append((x, min(CGFloat(projCum / yMax), 1.4)))
                }
            }
        }

        return (actual, projected, CGFloat(Double(limit) / yMax))
    }

    private func ymdToday() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

// MARK: - Copilot section

private struct CopilotSectionView: View {
    @ObservedObject var vm: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "GITHUB COPILOT",
                dotColor: vm.isGitHubConnected ? .green : Color(NSColor.tertiaryLabelColor),
                statusLabel: vm.isGitHubConnected ? "Connected" : "Not connected"
            )

            if !vm.isGitHubConnected {
                Text("Connect your GitHub account to track Copilot usage.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let usage = vm.copilotUsage {
                CopilotUsageRowView(usage: usage)
            } else {
                Text("Fetching usage…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Copilot usage row

private struct CopilotUsageRowView: View {
    let usage: CopilotUsage

    private var projectedPct: Double? { usage.projectedEndPercentage }
    private var isOverBudget: Bool { (projectedPct ?? 0) > 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Usage header
            HStack {
                Text("Premium requests")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.1f%%", usage.percentage))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(pctColor(usage.percentage))
            }

            UsageBar(
                value: usage.percentage / 100,
                projectedValue: (projectedPct ?? usage.percentage) / 100,
                color: isOverBudget ? .orange : .purple
            )

            CopilotCumulativeChart(usage: usage)
                .frame(height: 52)

            // Projection row
            HStack {
                if let proj = projectedPct {
                    if isOverBudget {
                        Label(String(format: "Proj. %.0f%%", proj), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    } else {
                        Text(String(format: "Proj. %.0f%%", proj))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Not enough data yet")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Reset row — always prominent
            Divider().opacity(0.2)
            CopilotResetRow(usage: usage)
        }
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return .primary
        case ..<90: return .orange
        default:    return .red
        }
    }
}

// MARK: - Copilot reset row

private struct CopilotResetRow: View {
    let usage: CopilotUsage

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Resets")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formattedResetDate)
                    .font(.system(size: 11, weight: .semibold))
                Text(daysLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var formattedResetDate: String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: usage.resetDate)
    }

    private var daysLabel: String {
        let d = usage.daysRemaining
        if d == 0 { return "Today" }
        if d == 1 { return "Tomorrow" }
        return "in \(d) days"
    }
}

// MARK: - Copilot cumulative chart

private struct CopilotCumulativeChart: View {
    let usage: CopilotUsage

    private var chartData: (actual: [(CGFloat, CGFloat)], projected: [(CGFloat, CGFloat)], limitY: CGFloat) {
        let series = usage.monthlySeries()
        guard !series.isEmpty else { return ([], [(0, 0), (1, 0)], 1.0) }

        let yMax: CGFloat = 150
        var actual:    [(CGFloat, CGFloat)] = []
        var projected: [(CGFloat, CGFloat)] = []
        let total = CGFloat(series.count)

        for pt in series {
            let x = CGFloat(pt.day) / total
            let y = CGFloat(pt.cumPct) / yMax
            if !pt.isProjected { actual.append((x, y)) }
            else               { projected.append((x, min(y, 1.4))) }
        }
        if let bridge = actual.last { projected.insert(bridge, at: 0) }

        return (actual, projected, 100 / yMax)
    }

    var body: some View {
        let (actual, projected, limitY) = chartData
        CumulativeLineChart(actualPoints: actual, projectedPoints: projected, referenceY: limitY, color: .purple)
    }
}

// MARK: - Shared cumulative line chart (Canvas)

private struct CumulativeLineChart: View {
    let actualPoints:    [(CGFloat, CGFloat)]
    let projectedPoints: [(CGFloat, CGFloat)]
    var referenceY: CGFloat? = nil
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let dotStroke: Color = colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.15)
            let refColor:  Color = .red.opacity(colorScheme == .dark ? 0.50 : 0.40)

            let draw: [(CGFloat, CGFloat)]
            if actualPoints.count == 1, let pt = actualPoints.first, pt.0 > 0 {
                draw = [(0, 0), pt]
            } else {
                draw = actualPoints
            }

            // ── Reference line ────────────────────────────────────
            if let refY = referenceY, refY > 0, refY <= 1.2 {
                let ry = h - refY * h
                var p = Path(); p.move(to: CGPoint(x: 0, y: ry)); p.addLine(to: CGPoint(x: w, y: ry))
                ctx.stroke(p, with: .color(refColor), style: StrokeStyle(lineWidth: 0.75, dash: [3, 2]))
            }

            // ── Area fill ─────────────────────────────────────────
            if draw.count >= 2 {
                var fill = Path()
                fill.move(to: CGPoint(x: draw[0].0 * w, y: h))
                for (x, y) in draw { fill.addLine(to: CGPoint(x: x * w, y: h - y * h)) }
                fill.addLine(to: CGPoint(x: draw.last!.0 * w, y: h))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color.opacity(colorScheme == .dark ? 0.15 : 0.10)))
            }

            // ── Solid line ────────────────────────────────────────
            if draw.count >= 2 {
                var line = Path()
                line.move(to: CGPoint(x: draw[0].0 * w, y: h - draw[0].1 * h))
                for (x, y) in draw.dropFirst() { line.addLine(to: CGPoint(x: x * w, y: h - y * h)) }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }

            // ── Projected dashed line ─────────────────────────────
            if projectedPoints.count >= 2 {
                var line = Path()
                line.move(to: CGPoint(x: projectedPoints[0].0 * w, y: h - min(projectedPoints[0].1, 1.3) * h))
                for (x, y) in projectedPoints.dropFirst() {
                    line.addLine(to: CGPoint(x: x * w, y: h - min(y, 1.3) * h))
                }
                ctx.stroke(line, with: .color(color.opacity(0.40)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3]))
            }

            // ── Today dot ─────────────────────────────────────────
            if let pt = draw.last ?? projectedPoints.first {
                let cx = pt.0 * w; let cy = h - min(pt.1, 1.3) * h
                let dot = Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
                ctx.fill(dot, with: .color(color))
                ctx.stroke(dot, with: .color(dotStroke), lineWidth: 1.5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
    }
}

// MARK: - Shared primitives

private struct UsageBar: View {
    let value: Double
    var projectedValue: Double? = nil
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                if let proj = projectedValue, proj > value {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.20))
                        .frame(width: min(w * proj, w))
                }
                if value > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.gradient)
                        .frame(width: min(w * value, w))
                }
            }
        }
        .frame(height: 5)
    }
}

private struct SectionHeader: View {
    let title: String
    let dotColor: Color
    let statusLabel: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .tracking(0.5)
            Spacer()
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(statusLabel)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers

private func formatTokens(_ t: Int) -> String {
    if t >= 1_000_000 { return String(format: "%.1fM", Double(t) / 1_000_000) }
    if t >= 1_000     { return String(format: "%.1fK", Double(t) / 1_000) }
    return "\(t)"
}

private func formatDuration(_ t: TimeInterval) -> String {
    let total = max(Int(t), 0)
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "<1m"
}

private extension ClaudeCLIStatus {
    var dotColor: Color {
        switch self {
        case .connected:        return .green
        case .notAuthenticated: return .orange
        case .notInstalled:     return Color(NSColor.tertiaryLabelColor)
        }
    }
    var label: String {
        switch self {
        case .connected:        return "Connected"
        case .notAuthenticated: return "Not auth."
        case .notInstalled:     return "Not installed"
        }
    }
}
