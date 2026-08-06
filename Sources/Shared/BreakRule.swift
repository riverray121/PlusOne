import Foundation
import FamilyControls

// One scheduled break: the selection opens without a selfie at the set time
// every day, for `minutes` of combined use spendable anywhere in a window of
// `windowMinutes`. The usage threshold is the real limit and the window end
// is the backstop.
struct BreakRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var selection = FamilyActivitySelection()
    // Daily start, as minutes after local midnight.
    var startMinuteOfDay = 8 * 60
    var minutes = 5
    // Window length; DeviceActivity rejects schedules shorter than 15
    // minutes, so this never goes below that.
    var windowMinutes = 15

    init() {}

    // windowMinutes is decoded leniently so rules persisted without the key
    // still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        selection = try container.decode(FamilyActivitySelection.self, forKey: .selection)
        startMinuteOfDay = try container.decode(Int.self, forKey: .startMinuteOfDay)
        minutes = try container.decode(Int.self, forKey: .minutes)
        windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes) ?? max(15, minutes + 1)
    }

    private enum CodingKeys: String, CodingKey {
        case id, selection, startMinuteOfDay, minutes, windowMinutes
    }

    var itemCount: Int {
        selection.itemCount
    }

    var startHour: Int { startMinuteOfDay / 60 }
    var startMinute: Int { startMinuteOfDay % 60 }

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
