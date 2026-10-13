import SwiftUI

/// Settings page "Phone Numbers": which app opens internal and other numbers.
struct PhoneNumbersSettingsView: View {
    var body: some View {
        List {
            ForEach(PhoneNumberKind.allCases) { kind in
                CallPreferenceSection(kind: kind)
            }
        }
        .navigationTitle("Phone Numbers")
    }
}
