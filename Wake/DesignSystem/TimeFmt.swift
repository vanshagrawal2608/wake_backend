import Foundation

enum TimeFmt {
    static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    static func clock(_ date: Date) -> String { clockFmt.string(from: date) }
}
