import Foundation

/// Only persisted input belongs in this snapshot, not focus, disclosure, or loading state.
struct FormDraftSnapshot: Equatable {
    var text: [String] = []
    var dates: [Date] = []
    var flags: [Bool] = []
    var ids: [UUID] = []
    var numbers: [Int] = []
    var images: [Data] = []
}

struct FormDraftState {
    private var baseline: FormDraftSnapshot?

    mutating func captureBaseline(_ snapshot: FormDraftSnapshot) {
        if baseline == nil { baseline = snapshot }
    }

    func hasChanges(comparedTo snapshot: FormDraftSnapshot) -> Bool {
        baseline.map { $0 != snapshot } ?? false
    }
}

enum FormInputNavigation {
    static func next<Field: Hashable>(after current: Field?, in fields: [Field]) -> Field? {
        guard let current, let index = fields.firstIndex(of: current), index + 1 < fields.count else { return nil }
        return fields[index + 1]
    }
}
