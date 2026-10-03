#if os(iOS)
import SwiftUI

/// One switch action across the complete, growing row. Native switch-style
/// Toggle exposes its label in AX but does not make that whole label/padding a
/// physical hit target. A native Button owns the row; the switch is decoration.
/// The public accessibility representation retains native switch semantics and
/// routes assistive activation through the same caller-owned binding.
struct A11ySwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Spacing.s2) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: configuration.$isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
#endif
