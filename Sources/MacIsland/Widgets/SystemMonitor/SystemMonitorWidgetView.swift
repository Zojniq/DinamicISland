import SwiftUI

/// Sleek hardware dashboard displaying live CPU load, RAM allocation, and battery status.
struct SystemMonitorWidgetView: View {
    @ObservedObject var service: SystemMonitorService

    var body: some View {
        HStack(spacing: 8) {
            // CPU Metric
            metricCard(
                title: "CPU",
                valueText: String(format: "%.0f%%", service.cpuUsage),
                detailText: "Load",
                progress: service.cpuUsage / 100.0,
                tint: cpuTint,
                icon: "cpu"
            )

            // RAM Metric
            metricCard(
                title: "RAM",
                valueText: String(format: "%.1fG", service.memoryUsedGB),
                detailText: String(format: "of %.0fG", service.memoryTotalGB),
                progress: service.memoryUsage,
                tint: memoryTint,
                icon: "memorychip"
            )

            // Battery Metric
            metricCard(
                title: "BATTERY",
                valueText: "\(service.batteryLevel)%",
                detailText: service.isCharging ? "Charging" : (service.hasBattery ? "On Battery" : "AC Power"),
                progress: Double(service.batteryLevel) / 100.0,
                tint: batteryTint,
                icon: batteryIcon
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandCard()
    }

    private func metricCard(
        title: String,
        valueText: String,
        detailText: String,
        progress: Double,
        tint: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.3)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detailText)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(geo.size.width * min(max(progress, 0.0), 1.0), 3))
                }
            }
            .frame(height: 3)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var cpuTint: Color {
        if service.cpuUsage > 80 {
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        } else if service.cpuUsage > 50 {
            return Color(red: 1.0, green: 0.75, blue: 0.3)
        } else {
            return Color(red: 0.35, green: 0.85, blue: 0.55)
        }
    }

    private var memoryTint: Color {
        if service.memoryUsage > 0.85 {
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        } else if service.memoryUsage > 0.70 {
            return Color(red: 1.0, green: 0.75, blue: 0.3)
        } else {
            return Color(red: 0.4, green: 0.75, blue: 1.0)
        }
    }

    private var batteryTint: Color {
        if service.isCharging {
            return Color(red: 0.35, green: 0.9, blue: 0.55)
        } else if service.batteryLevel <= 20 {
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        } else {
            return Color.white.opacity(0.85)
        }
    }

    private var batteryIcon: String {
        if service.isCharging {
            return "battery.100.bolt"
        }
        switch service.batteryLevel {
        case 0...20:   return "battery.25"
        case 21...50:  return "battery.50"
        case 51...75:  return "battery.75"
        default:       return "battery.100"
        }
    }
}
