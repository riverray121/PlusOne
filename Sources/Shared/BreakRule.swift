import Foundation
import FamilyControls

// One scheduled break: the selection opens without a selfie at the set time
// every day, for `minutes` of combined use. Enforcement mirrors unlock
// sessions: the usage threshold is the real limit and the interval end is the
// backstop, so the minutes can be spent any time within the window.
struct BreakRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var selection = FamilyActivitySelection()
    // Daily start, as minutes after local midnight.
    var startMinuteOfDay = 8 * 60
    var minutes = 5

    var itemCount: Int {
        selection.itemCount
    }

    var startHour: Int { startMinuteOfDay / 60 }
    var startMinute: Int { startMinuteOfDay % 60 }

    // DeviceActivity rejects schedules shorter than 15 minutes, so the window
    // is at least that long; total use is still capped at `minutes`.
    var windowMinutes: Int { max(15, minutes + 1) }

    var timeLabel: String {
        let date = Calendar.current.date(
            bySettingHour: startHour,
            minute: startMinute,
            second: 0,
            of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
