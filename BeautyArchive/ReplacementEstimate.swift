import Foundation

struct ReplacementEstimate {
    enum Source {
        case manual
        case history(Int)
        case adjusted

        var title: String {
            switch self {
            case .manual: "設定した日数"
            case .history(let count): "使い切り履歴（\(count)件）の中央値"
            case .adjusted: "調整した日数"
            }
        }
    }

    let date: Date
    let usageDays: Int
    let source: Source

    static func calculate(
        for unit: ProductUnit,
        among units: [ProductUnit],
        calendar: Calendar = .current
    ) -> ReplacementEstimate? {
        guard unit.usesReplacementEstimate,
              unit.status == .inUse,
              let openedAt = unit.openedAt
        else { return nil }

        let history = units.compactMap { previous -> Int? in
            guard previous.productID == unit.productID,
                  previous.id != unit.id,
                  previous.status == .finished,
                  let previousOpenedAt = previous.openedAt,
                  let previousFinishedAt = previous.finishedAt,
                  calendar.startOfDay(for: previousOpenedAt) < calendar.startOfDay(for: openedAt)
            else { return nil }
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: previousOpenedAt),
                to: calendar.startOfDay(for: previousFinishedAt)
            ).day ?? 0
            return days > 0 ? days : nil
        }.sorted()

        let historicalDays: Int? = history.isEmpty ? nil : {
            let middle = history.count / 2
            return history.count.isMultiple(of: 2)
                ? (history[middle - 1] + history[middle]) / 2
                : history[middle]
        }()

        let days: Int
        let source: Source
        if let adjusted = unit.adjustedUsageDays, adjusted > 0 {
            days = adjusted
            source = .adjusted
        } else if let historicalDays {
            days = historicalDays
            source = .history(history.count)
        } else if let manual = unit.manualUsageDays, manual > 0 {
            days = manual
            source = .manual
        } else {
            return nil
        }

        guard let date = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: openedAt))
        else { return nil }
        return ReplacementEstimate(date: date, usageDays: days, source: source)
    }
}
