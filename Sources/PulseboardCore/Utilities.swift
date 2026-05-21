import Foundation
import SwiftUI

public enum ByteFormatter {
    public static func string(_ bytes: UInt64, precision: Int = 1) -> String {
        let value = Double(bytes)
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = value
        var unitIndex = 0

        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaled)) \(units[unitIndex])"
        }

        return String(format: "%.\(precision)f %@", scaled, units[unitIndex])
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        string(UInt64(max(0, bytesPerSecond)), precision: 1) + "/s"
    }
}

public extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch sanitized.count {
        case 3:
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
            alpha = 255
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 255
        case 8:
            red = (value >> 24) & 0xFF
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        default:
            red = 61
            green = 214
            blue = 167
            alpha = 255
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

public extension Double {
    var percentText: String {
        String(format: "%.0f%%", self)
    }
}

public extension ProcessMetric {
    func valueText(for column: ProcessColumn) -> String {
        switch column {
        case .name:
            name
        case .pid:
            String(pid)
        case .cpu:
            String(format: "%.1f", cpuPercent)
        case .memory:
            ByteFormatter.string(residentMemory)
        case .threads:
            String(threadCount)
        case .user:
            String(uid)
        case .path:
            path.isEmpty ? "Unavailable" : path
        }
    }
}

public extension Array where Element == ProcessMetric {
    func filtered(_ query: String) -> [ProcessMetric] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }

        return filter { process in
            process.name.localizedCaseInsensitiveContains(trimmed)
                || String(process.pid).contains(trimmed)
                || process.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func sorted(using sort: ProcessSort) -> [ProcessMetric] {
        sorted { left, right in
            let comparison: ComparisonResult
            switch sort.column {
            case .name:
                comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            case .pid:
                comparison = left.pid == right.pid ? .orderedSame : (left.pid < right.pid ? .orderedAscending : .orderedDescending)
            case .cpu:
                comparison = left.cpuPercent == right.cpuPercent ? .orderedSame : (left.cpuPercent < right.cpuPercent ? .orderedAscending : .orderedDescending)
            case .memory:
                comparison = left.residentMemory == right.residentMemory ? .orderedSame : (left.residentMemory < right.residentMemory ? .orderedAscending : .orderedDescending)
            case .threads:
                comparison = left.threadCount == right.threadCount ? .orderedSame : (left.threadCount < right.threadCount ? .orderedAscending : .orderedDescending)
            case .user:
                comparison = left.uid == right.uid ? .orderedSame : (left.uid < right.uid ? .orderedAscending : .orderedDescending)
            case .path:
                comparison = left.path.localizedCaseInsensitiveCompare(right.path)
            }

            if comparison == .orderedSame {
                return left.pid < right.pid
            }

            return sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
