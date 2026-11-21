import SwiftUI

// Toolbar shared by the rule editors. An existing rule opens read-only with
// the system back button and Edit. Editing swaps in Cancel and Save and hides
// the back button, so unsaved edits are never dropped by a back swipe. Cancel
// on an existing rule reverts and returns to read-only; on a new rule, which
// opens already editing, it leaves. Save always leaves: a saved change can
// queue behind the anti-tamper delay, and the screen would otherwise show
// values that are not in effect.
private struct RuleEditorChrome: ViewModifier {
    @Binding var editing: Bool
    let isNew: Bool
    let canSave: Bool
    let revert: () -> Void
    let save: () -> Void

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(editing)
            .numberPadDoneButton()
            .toolbar {
                if editing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if isNew {
                                dismiss()
                            } else {
                                revert()
                                editing = false
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save()
                            dismiss()
                        }
                        .bold()
                        .tint(.blue)
                        .disabled(!canSave)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { editing = true }
                    }
                }
            }
    }
}

extension View {
    func ruleEditorChrome(
        editing: Binding<Bool>,
        isNew: Bool,
        canSave: Bool,
        revert: @escaping () -> Void,
        save: @escaping () -> Void
    ) -> some View {
        modifier(RuleEditorChrome(editing: editing, isNew: isNew, canSave: canSave, revert: revert, save: save))
    }
}

// A read-only settings row: title on the left, value on the right.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
