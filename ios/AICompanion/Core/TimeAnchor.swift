import Foundation

/// 时间锚：让模型知道「今天几号、现在几点、认识多久、上次聊是什么时候」。
/// 没有这一行，「前天」「上次」「好久没聊」这些词在模型眼里全是空的。
enum TimeAnchor {

    static func line(for characterID: String, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let day = calendar.component(.day, from: now)
        let month = calendar.component(.month, from: now)
        let weekday = weekdayName(calendar.component(.weekday, from: now))
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        var text = String(format: "【时间】现在是 %d 月 %d 日 %@ %@ %02d:%02d。",
                          month, day, weekday, period(hour), hour, minute)

        let firstSeen = ChatMemoryStore.shared.firstSeen(characterID: characterID)
            ?? ChatMemoryStore.shared.turns(for: characterID).first?.date
        if let firstSeen {
            let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: firstSeen),
                                                      to: calendar.startOfDay(for: now)).day! + 1)
            text += "你们认识第 \(days) 天"
            if let gap = ChatMemoryStore.shared.gapHours(for: characterID) {
                text += "，上次聊天是\(gapText(gap))。"
            } else {
                text += "。"
            }
        } else {
            text += "今天是你们第一次说话。"
        }
        return text
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
    }

    private static func period(_ hour: Int) -> String {
        switch hour {
        case 0...5: return "深夜"
        case 6...8: return "清晨"
        case 9...11: return "上午"
        case 12...13: return "中午"
        case 14...17: return "下午"
        case 18...19: return "傍晚"
        default: return "夜里"
        }
    }

    private static func gapText(_ hours: Double) -> String {
        if hours < 1 { return "刚刚" }
        if hours < 24 { return "\(Int(hours)) 小时前" }
        if hours < 48 { return "昨天" }
        return "\(Int(hours / 24)) 天前"
    }
}
