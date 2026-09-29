import SwiftUI
import UIKit

extension View {
    func guardUnsavedDraft(_ snapshot: FormDraftSnapshot, onDiscard: @escaping () -> Void = { }) -> some View {
        modifier(UnsavedDraftModifier(snapshot: snapshot, onDiscard: onDiscard))
    }

    func formKeyboard<Field: Hashable>(
        _ focus: FocusState<Field?>.Binding, fields: [Field]
    ) -> some View {
        modifier(FormKeyboardModifier(focus: focus, fields: fields))
    }

    func formField<Field: Hashable>(
        _ focus: FocusState<Field?>.Binding, equals field: Field, last: Bool = false
    ) -> some View {
        focused(focus, equals: field).submitLabel(last ? .done : .next)
    }
}

struct FormValidationHint: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FormKeyboardModifier<Field: Hashable>: ViewModifier {
    let focus: FocusState<Field?>.Binding
    let fields: [Field]

    private var nextField: Field? {
        FormInputNavigation.next(after: focus.wrappedValue, in: fields)
    }

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .onSubmit { focus.wrappedValue = nextField }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focus.wrappedValue != nil {
                        if let nextField {
                            Button("次へ") { focus.wrappedValue = nextField }
                        }
                        Spacer()
                        Button("完了") { focus.wrappedValue = nil }
                    }
                }
            }
    }
}

private struct UnsavedDraftModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let snapshot: FormDraftSnapshot
    let onDiscard: () -> Void
    @State private var draftState = FormDraftState()
    @State private var showingDiscard = false

    private var hasChanges: Bool { draftState.hasChanges(comparedTo: snapshot) }

    func body(content: Content) -> some View {
        content
            .onAppear { draftState.captureBaseline(snapshot) }
            .interactiveDismissDisabled(hasChanges)
            .background(SheetDismissObserver(
                hasChanges: hasChanges, onAttempt: { showingDiscard = true }, onDismiss: onDiscard
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasChanges { showingDiscard = true } else { onDiscard(); dismiss() }
                    }
                }
            }
            .confirmationDialog("入力内容を破棄しますか？", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { onDiscard(); dismiss() }
                Button("入力を続ける", role: .cancel) { }
            } message: {
                Text("保存していない変更は失われます。")
            }
    }
}

/// SwiftUI prevents the swipe; UIKit's documented delegate callback reports the attempt.
/// Forward the existing delegate's methods so SwiftUI still owns presentation/dismissal.
private struct SheetDismissObserver: UIViewControllerRepresentable {
    let hasChanges: Bool
    let onAttempt: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> ObserverController { ObserverController() }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.proxy.hasChanges = hasChanges
        controller.proxy.onAttempt = onAttempt
        controller.proxy.onDismiss = onDismiss
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }

    static func dismantleUIViewController(_ controller: ObserverController, coordinator: ()) {
        controller.restore()
    }

    final class ObserverController: UIViewController {
        let proxy = DelegateProxy()
        weak var observedPresentation: UIPresentationController?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        func install() {
            var ancestor: UIViewController? = self
            while let controller = ancestor {
                if controller.presentingViewController != nil,
                   let presentation = controller.presentationController {
                    if observedPresentation !== presentation { restore() }
                    if presentation.delegate !== proxy {
                        proxy.original = presentation.delegate
                        observedPresentation = presentation
                        presentation.delegate = proxy
                    }
                    return
                }
                ancestor = controller.parent
            }
        }

        func restore() {
            if observedPresentation?.delegate === proxy {
                observedPresentation?.delegate = proxy.original
            }
            observedPresentation = nil
            proxy.original = nil
        }
    }

    final class DelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var original: (any UIAdaptivePresentationControllerDelegate)?
        var hasChanges = false
        var onAttempt: () -> Void = { }
        var onDismiss: () -> Void = { }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !hasChanges && (original?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if hasChanges { onAttempt() }
            else { original?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            onDismiss()
            original?.presentationControllerDidDismiss?(presentationController)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
