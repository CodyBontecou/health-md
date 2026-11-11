#if os(iOS)
import SwiftUI

/// A native popover containing native, growing SwiftUI Buttons. UIKit's Menu
/// action rows are 42pt on iOS 26.5 and ignore a SwiftUI label's minimum frame.
/// Owning the option views lets the real targets stay >=44pt without altering
/// option strings, shrinking text, or replacing the caller's selection policy.
struct A11ySelectionMenu<Value: Hashable, Label: View>: View {
    let selection: Value
    let options: [Value]
    let optionLabel: (Value) -> Text
    let onSelect: (Value) -> Void
    @ViewBuilder var label: () -> Label
    @State private var isPresented = false
    @ScaledMetric(relativeTo: .body) private var preferredRowHeight: CGFloat = 44

    var body: some View {
        Button { isPresented = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented) {
                // Ideal size is only a window preference. The native popover
                // constrains this scroll to its actual remaining screen space.
                ScrollView {
                    VStack(spacing: Spacing.s1) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                onSelect(option)
                                isPresented = false
                            } label: {
                                HStack(spacing: Spacing.s2) {
                                    optionLabel(option)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if selection == option {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                                .padding(Spacing.s3)
                                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                                .background(selection == option ? Color.selectedBackground : Color.bgPrimary,
                                            in: RoundedRectangle(cornerRadius: GeistRadius.sm))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selection == option ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selection == option ? .isSelected : [])
                        }
                    }
                    .padding(Spacing.s2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(idealWidth: 300, maxWidth: 400,
                       idealHeight: min(360, preferredRowHeight * CGFloat(options.count) + Spacing.s4), maxHeight: 360)
                .background(Color.bgPrimary)
                .presentationCompactAdaptation(.popover)
            }
    }
}
#endif
