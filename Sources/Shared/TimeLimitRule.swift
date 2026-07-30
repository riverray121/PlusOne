import Foundation
import FamilyControls

// One usage budget: the selection shares `minutes` of combined use per period,
// counted by a DeviceActivity usage threshold. A spent rule shields with no
// unlock until the period window rolls over.
struct TimeLimitRule: Codable, Identifiable, Equatable {
    enum Period: String, Codable, CaseIterable {
        case hour
        case day

        var label: String {
            self == .hour ? "hour" : "day"
        }
    }

    var id = UUID()
    var selection = FamilyActivitySelection()
    var minutes = 15
    var period = Period.day
    // Minutes-remaining mark for this rule's warning notification. 0 = off.
    var warnMinutes = 1

    init() {}

    // warnMinutes is decoded leniently so rules persisted without the key
    // still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        selection = try container.decode(FamilyActivitySelection.self, forKey: .selection)
        minutes = try container.decode(Int.self, forKey: .minutes)
        period = try container.decode(Period.self, forKey: .period)
        warnMinutes = try container.decodeIfPresent(Int.self, forKey: .warnMinutes) ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case id, selection, minutes, period, warnMinutes
    }

    var itemCount: Int {
        selection.itemCount
    }

    // Periods are calendar windows, not rolling: the budget resets at the top
    // of the next hour or at midnight.
    func nextReset(after date: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch period {
        case .hour:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? date.addingTimeInterval(3600)
        case .day:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            return calendar.startOfDay(for: tomorrow)
        }
    }
}
