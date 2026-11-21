import SwiftUI
import UIKit

// A settings row holding a typed whole number in the unit the user picks.
// `value` is stored in the smallest unit (minutes, or a plain count) and is
// clamped to `range` on every edit, so callers always read a valid value even
// when Save is tapped mid-edit. The text is rewritten to the clamped value
// once the field loses focus.
struct NumberField: View {
    struct Unit: Hashable {
        let label: String
        let factor: Int

        static let minutes = Unit(label: "min", factor: 1)
        static let hours = Unit(label: "hours", factor: 60)
        static let days = Unit(label: "days", factor: 24 * 60)
    }

    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var units: [Unit] = [.minutes]
    // Called when an edit is finished: focus leaves the field or the unit
    // changes while unfocused.
    var onCommit: () -> Void = {}

    @State private var text = ""
    @State private var unit: Unit = .minutes
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(maxWidth: 80)
            if units.count > 1 {
                Picker(title, selection: $unit) {
                    ForEach(units, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(unit.label)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: syncFromValue)
        .onChange(of: text) { _ in applyText() }
        .onChange(of: unit) { _ in
            applyText()
            if !focused {
                syncText()
                onCommit()
            }
        }
        .onChange(of: focused) { isFocused in
            guard !isFocused else { return }
            syncText()
            onCommit()
        }
        // A caller can move the value (a dependent limit shrinking); follow
        // it unless the user is typing.
        .onChange(of: value) { _ in
            if !focused { syncText() }
        }
        .onChange(of: range) { _ in
            let clamped = clamp(value)
            if clamped != value { value = clamped }
        }
    }

    private func clamp(_ n: Int) -> Int {
        min(max(n, range.lowerBound), range.upperBound)
    }

    private func applyText() {
        let typed = Int(text.filter(\.isNumber)) ?? 0
        let (product, overflow) = typed.multipliedReportingOverflow(by: unit.factor)
        let clamped = overflow ? range.upperBound : clamp(product)
        if clamped != value { value = clamped }
    }

    // Shows the value in the largest unit that divides it evenly.
    private func syncFromValue() {
        unit = units
            .sorted { $0.factor > $1.factor }
            .first { value > 0 && value % $0.factor == 0 } ?? units[0]
        syncText()
    }

    private func syncText() {
        if value % unit.factor != 0 {
            unit = units.first { value % $0.factor == 0 } ?? units[0]
        }
        text = String(value / unit.factor)
    }
}

extension View {
    // The number pad has no return key; this puts a Done button above it.
    // Apply once per screen, not per field, or the buttons stack up.
    func numberPadDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
