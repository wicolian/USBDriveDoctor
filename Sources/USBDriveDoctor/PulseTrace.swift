import SwiftUI

/// The signature element: a live trace line, like a bedside monitor strip,
/// synthesized from the actual kernel log stream rather than decoration.
///
/// A steady, nearly-flat line means the log has been quiet. Every warning
/// line (a real "hardware connection lost" / "aborting" event, not a guess)
/// draws one real spike at the moment it happened, which then settles back
/// to baseline. Nothing here is a canned animation - it is a direct,
/// honest visualization of "signal vs noise" for this exact drive.
struct PulseTrace: View {
    let entries: [LogEntry]
    let status: OverallStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var traceColor: Color {
        switch status {
        case .quiet: return Theme.textMuted
        case .healthy: return Theme.signalHealthy
        case .struggling: return Theme.critical
        }
    }

    var body: some View {
        Group {
            if reduceMotion {
                // Reduced motion: no scrolling animation, just an honest
                // static shape for the current state - flat if healthy,
                // a single held spike if struggling.
                staticTrace
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 24)) { timeline in
                    Canvas { context, size in
                        draw(context: &context, size: size, now: timeline.date)
                    }
                }
            }
        }
        .frame(height: 28)
        .drawingGroup()
    }

    private var staticTrace: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            if status == .struggling {
                let midX = size.width * 0.5
                path.addLine(to: CGPoint(x: midX - 6, y: midY))
                path.addLine(to: CGPoint(x: midX, y: midY - size.height * 0.38))
                path.addLine(to: CGPoint(x: midX + 6, y: midY))
            }
            path.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(path, with: .color(traceColor), lineWidth: 1.4)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, now: Date) {
        let midY = size.height * 0.55
        let baseAmplitude: CGFloat = status == .quiet ? 0 : 1.4
        let window: TimeInterval = 8 // seconds of history shown across the width

        var path = Path()
        let steps = Int(size.width)
        for x in stride(from: 0, through: steps, by: 2) {
            let t = now.addingTimeInterval(-window * (1 - Double(x) / Double(max(steps, 1))))
            let y = midY - amplitude(at: t, baseAmplitude: baseAmplitude, now: now)
            let point = CGPoint(x: CGFloat(x), y: y)
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(traceColor), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }

    /// A gentle idle wobble when healthy (barely there - this should read
    /// as "alive," never as a distraction), plus a real decaying spike for
    /// every warning line that actually happened near time `t`.
    private func amplitude(at t: Date, baseAmplitude: CGFloat, now: Date) -> CGFloat {
        var y: CGFloat = baseAmplitude * CGFloat(sin(t.timeIntervalSinceReferenceDate * 1.6)) * 1.2

        for entry in entries.suffix(40) where entry.isWarning {
            let dt = t.timeIntervalSince(entry.timestamp)
            guard dt > -0.05, dt < 1.2 else { continue }
            // Fast rise, short decay - one honest spike per real event.
            let decay = exp(-dt * 4.5)
            let spike = 11.0 * decay * sin(min(dt, 0.15) / 0.15 * .pi)
            y += CGFloat(spike)
        }
        return y
    }
}
