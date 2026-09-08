import SwiftUI

/// Register as `dialogs` in the central isolated host. Uses the actual production
/// overlay/card/fields; all drafts and callbacks below are synthetic in-memory state.
/// No settings, configuration-protection, billing or HealthKit behavior is simulated.
struct DialogsA11yScenario: View {
    private enum Example { case message, fields, singleField, manyActions, noCancel, secondaryFields }

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var example: Example = .message
    @State private var presented = false
    @State private var first = ""
    @State private var second = ""
    @State private var saves = 0
    @State private var cancels = 0
    @State private var removes = 0
    @State private var dismissals = 0
    @State private var events: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                opener("Open Fields", id: "fields", example: .fields)
                opener("Open Message", id: "message", example: .message)
                opener("Open Single Field", id: "single", example: .singleField)
                opener("Open Many Actions", id: "many", example: .manyActions)
                opener("Open Without Cancel", id: "no-cancel", example: .noCancel)
                opener("Open Secondary Fields", id: "secondary-fields", example: .secondaryFields)
                Text(verbatim: "s\(saves) c\(cancels) r\(removes) d\(dismissals)")
                    .accessibilityIdentifier("a11y.dialogs.counts")
                Text(verbatim: events.joined(separator: "|"))
                    .accessibilityIdentifier("a11y.dialogs.events")
                Text(verbatim: "First: \(first)").accessibilityIdentifier("a11y.dialogs.first-value")
                Text(verbatim: "Second: \(second)").accessibilityIdentifier("a11y.dialogs.second-value")
                Text(verbatim: reduceMotion ? "Reduced motion: on" : "Reduced motion: off")
                    .accessibilityIdentifier("a11y.dialogs.motion")
            }
            .font(Typography.body())
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
        }
        .background(Color.bgPrimary)
        .geistDialog(
            isPresented: presentation,
            title: Text(verbatim: example == .message ? messageTitle : "Synthetic Fields"),
            message: Text(verbatim: example == .message ? longMessage : "Edit synthetic drafts only. No settings are saved."),
            messageAccessibilityIdentifier: "a11y.dialogs.message",
            actions: actions,
            fields: fields
        )
    }

    private func opener(_ label: LocalizedStringKey, id: String, example: Example) -> some View {
        GeistDialogActionButton(action: .action(label, accessibilityIdentifier: "a11y.dialogs.open-\(id)") {
            self.example = example
            first = ""
            second = ""
            saves = 0
            cancels = 0
            removes = 0
            dismissals = 0
            events = []
            presented = true
        }, onAction: { $0.handler() })
    }

    private var presentation: Binding<Bool> {
        Binding(get: { presented }, set: { value in
            if presented && !value {
                dismissals += 1
                events.append("dismiss")
            }
            presented = value
        })
    }

    private var actions: [GeistDialogAction] {
        let save = GeistDialogAction.action("Save Fields", accessibilityIdentifier: "a11y.dialogs.save") {
            saves += 1
            events.append("save:\(presented)")
        }
        let cancel = GeistDialogAction.cancel("Cancel", accessibilityIdentifier: "a11y.dialogs.cancel") {
            cancels += 1
            events.append("cancel:\(presented)")
        }
        switch example {
        case .message:
            return [
                .cancel("Cancel", accessibilityIdentifier: "a11y.dialogs.cancel") {
                    cancels += 1; events.append("cancel:\(presented)")
                },
                .action(LocalizedStringKey(messageAction), accessibilityIdentifier: "a11y.dialogs.save") {
                    saves += 1; events.append("save:\(presented)")
                }
            ]
        case .manyActions:
            // Deliberately interleave roles: quiet actions must remain first in the UI,
            // while Done still chooses the first caller-provided prominent action.
            return [save, cancel,
                    .destructive("Remove Draft", accessibilityIdentifier: "a11y.dialogs.remove") {
                        removes += 1; events.append("remove:\(presented)")
                    },
                    .cancel("Other Cancel", accessibilityIdentifier: "a11y.dialogs.other-cancel") {
                        cancels += 10; events.append("other-cancel:\(presented)")
                    }]
        case .noCancel: return [save]
        case .secondaryFields: return [cancel]
        case .fields, .singleField: return [cancel, save]
        }
    }

    private var fields: [GeistDialogField] {
        switch example {
        case .message, .manyActions, .noCancel: return []
        case .singleField:
            return [GeistDialogField(placeholder: "Field Name", text: $first)]
        case .fields, .secondaryFields:
            return [
                GeistDialogField(placeholder: "Field Name With a Complete External Label", text: $first),
                GeistDialogField(placeholder: "Field Value With a Different External Label", text: $second)
            ]
        }
    }

    private var messageTitle: String {
        switch locale.language.languageCode?.identifier {
        case "de": "Vollständige synthetische Erklärung"
        case "ar": "شرح اصطناعي كامل للقراءة"
        case "ja": "合成データの説明をすべて読む"
        default: "Read the Complete Synthetic Explanation"
        }
    }

    private var longMessage: String {
        let paragraph: String
        switch locale.language.languageCode?.identifier {
        case "de": paragraph = "Diese synthetische Erklärung bleibt bei der gewählten Textgröße vollständig lesbar. Es werden keine Einstellungen geändert. "
        case "ar": paragraph = "يبقى هذا الشرح الاصطناعي قابلاً للقراءة بحجم النص الذي تختاره. لا تتغير أي إعدادات. "
        case "ja": paragraph = "選択した文字サイズで、この合成データの説明をすべて読むことができます。設定は変更されません。"
        default: paragraph = "This synthetic explanation remains fully readable at the chosen text size. No settings are changed. "
        }
        return String(repeating: paragraph, count: 6) + " [END]"
    }

    private var messageAction: String {
        switch locale.language.languageCode?.identifier {
        case "de": "Erklärung Behalten"
        case "ar": "الاحتفاظ بالشرح"
        case "ja": "説明を保存する"
        default: "Keep Synthetic Explanation"
        }
    }
}
