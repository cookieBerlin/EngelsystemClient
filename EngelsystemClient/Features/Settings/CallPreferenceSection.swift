import SwiftUI

/// Settings section choosing which app opens numbers of one kind (`PhoneNumberKind`).
struct CallPreferenceSection: View {
    let kind: PhoneNumberKind
    @AppStorage private var raw: String

    init(kind: PhoneNumberKind) {
        self.kind = kind
        _raw = AppStorage(wrappedValue: "", CallPreference.userDefaultsKey(for: kind))
    }

    private var preference: CallPreference { CallPreference.decode(raw: raw) }

    private var appBinding: Binding<CallApp> {
        Binding(
            get: { preference.app },
            set: { raw = preference.switching(to: $0, kind: kind).encoded }
        )
    }

    private var actionBinding: Binding<CallAction> {
        Binding(
            get: { preference.action },
            set: {
                var updated = preference
                updated.action = $0
                raw = updated.encoded
            }
        )
    }

    private var templateBinding: Binding<String> {
        Binding(
            get: { preference.customTemplate },
            set: {
                var updated = preference
                updated.customTemplate = $0
                raw = updated.encoded
            }
        )
    }

    private var exampleNumber: String { kind == .internalNumber ? "1000" : "+49 30 1234567" }

    private var example: String {
        guard let number = PhoneNumber(exampleNumber), let url = preference.url(for: number) else {
            return preference.app == .custom ? "not usable yet" : "copy only"
        }
        return url.absoluteString
    }

    var body: some View {
        Section {
            Picker("Call With", selection: appBinding) {
                ForEach(CallApp.allCases) { app in
                    Text(app.title).tag(app)
                }
            }
            if preference.app.scheme != nil {
                Picker("Action", selection: actionBinding) {
                    ForEach(CallAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
            }
            if preference.app == .custom {
                TextField("Link template", text: templateBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if !CallPreference.isValidTemplate(preference.customTemplate) {
                    Text("The template needs {number} and a scheme such as myapp: (not http, https or file).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(kind.title)
        } footer: {
            Text("\(kind == .internalNumber ? "Numbers of up to five digits." : "All longer numbers.") Example for \(exampleNumber): \(example)")
        }
    }
}
