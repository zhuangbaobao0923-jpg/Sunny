import Foundation

/// 会话列表时间文案规则：
/// - 今天 → 「14:32」
/// - 昨天 → 「昨天 14:32」
/// - 更早 → 「8/14」
///
/// 气泡内时间统一走 `clock`（只显示时分）。纯函数，便于单测。
enum TimeLabel {
    static func listLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return clock(date, calendar: calendar)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + clock(date, calendar: calendar)
        }
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 1)/\(comps.day ?? 1)"
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
