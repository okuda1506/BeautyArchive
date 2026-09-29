import SwiftUI

struct PendingDeletion {
    let ids: [UUID]
    let names: [String]
    let consequence: String
}

extension View {
    func confirmDeletion(
        _ pending: Binding<PendingDeletion?>, delete: @escaping ([UUID]) -> Void
    ) -> some View {
        confirmationDialog(
            "削除しますか？",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { selection in
            Button("削除", role: .destructive) { delete(selection.ids) }
            Button("キャンセル", role: .cancel) { }
        } message: { selection in
            Text(selection.names.joined(separator: "\n") + "\n\n" + selection.consequence)
        }
    }
}
