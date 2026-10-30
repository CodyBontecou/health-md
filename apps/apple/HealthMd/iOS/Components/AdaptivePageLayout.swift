import SwiftUI

/// Uses the available window width so folding, Split View, and large text all
/// share the same fallback. Layout changes preserve the children's identities.
struct AdaptivePageColumns<Primary: View, Secondary: View>: View {
    let availableWidth: CGFloat
    var showsSecondary = true
    var spacing: CGFloat = Spacing.md
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = availableWidth >= 720 && !dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))

        layout {
            primary()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            if showsSecondary {
                secondary()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Keeps the existing page header and status components, placing status beside
/// the brand on wide windows and below the title in compact windows.
struct AdaptivePageHeader<Status: View>: View {
    let availableWidth: CGFloat
    let title: String
    let subtitle: String
    @ViewBuilder var status: () -> Status
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let usesColumns = availableWidth >= 720 && !dynamicTypeSize.isAccessibilitySize
        let layout = usesColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))

        layout {
            HealthMdPageHeader(title: title, subtitle: subtitle)
            status()
                .frame(
                    maxWidth: usesColumns ? (availableWidth - 3 * Spacing.md) / 2 : .infinity,
                    alignment: usesColumns ? .trailing : .leading
                )
                .padding(.top, usesColumns ? Spacing.s1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
