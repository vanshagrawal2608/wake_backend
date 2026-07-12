import Foundation

/// Persistence for every morning. Codable JSON on disk today; the interface is
/// deliberately narrow so it can move to SwiftData/CoreData without touching callers.
final class WakeStore {
    private let url: URL
    private(set) var records: [WakeRecord] = []

    init(filename: String = "wake-records.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(filename)
        load()
    }

    func append(_ record: WakeRecord) {
        records.append(record)
        save()
    }

    func update(_ record: WakeRecord) {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[i] = record
        save()
    }

    /// Most-recent-last wake durations, for the recency-weighted model.
    func recentWakeDurations(limit: Int = 21) -> [Double] {
        records.compactMap(\.wakeDurationMinutes).suffix(limit).map { $0 }
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.wake.decode([WakeRecord].self, from: data)
        else { records = WakeRecord.seed; return }   // seed so the UI has something to show
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.wake.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static let wake: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
extension JSONDecoder {
    static let wake: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}

// MARK: - Seed data (so Insights isn't empty on first launch)

extension WakeRecord {
    static var seed: [WakeRecord] {
        let cal = Calendar.current
        let durations = [31.0, 24, 29, 26, 33, 28, 26]
        return (0..<7).reversed().map { i in
            let day = cal.date(byAdding: .day, value: -i, to: .now)!
            let deadline = cal.date(bySettingHour: 8, minute: 50, second: 0, of: day)!
            let win = durations[6 - i]
            let start = deadline.addingTimeInterval(-win * 60)
            return WakeRecord(
                date: day,
                sleepStart: cal.date(byAdding: .hour, value: -8, to: start),
                deadline: deadline,
                windowStart: start,
                firstStageFired: start,
                dismissed: deadline.addingTimeInterval(Double.random(in: -180...120)),
                snoozeEquivalents: Int.random(in: 0...2),
                voiceConfirmed: Bool.random()
            )
        }
    }
}
