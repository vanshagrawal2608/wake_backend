import Foundation

enum TimeFmt {
    static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    static func clock(_ date: Date) -> String { clockFmt.string(from: date) }

    static let ampmFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "a"; return f
    }()
    static func ampm(_ date: Date) -> String { ampmFmt.string(from: date) }
}
