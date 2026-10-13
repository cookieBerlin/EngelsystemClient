import SwiftUI
import UIKit

/// One contact number (DECT or mobile): tapping opens it with the app chosen in Settings ›
/// Phone Numbers (`CallPreference`), the copy button and the long-press menu copy it. The
/// "internal short number" note shows only for numbers of up to five digits.
struct PhoneNumberRow: View {
    let label: String
    let value: String

    @Environment(\.openURL) private var openURL
    @AppStorage(CallPreference.userDefaultsKey(for: .internalNumber)) private var internalRaw = ""
    @AppStorage(CallPreference.userDefaultsKey(for: .otherNumber)) private var otherRaw = ""
    @State private var showsNoAppAlert = false

    private var number: PhoneNumber? { PhoneNumber(value) }

    private var url: URL? {
        guard let number else { return nil }
        let raw = number.kind == .internalNumber ? internalRaw : otherRaw
        return CallPreference.decode(raw: raw).url(for: number)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                if let url {
                    Button(value) {
                        openURL(url) { accepted in
                            if !accepted { showsNoAppAlert = true }
                        }
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(value).foregroundStyle(.secondary)
                }
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(label)")
            }
            if number?.kind == .internalNumber {
                Text("Internal short number — reachable from any DECT phone on site.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
        }
        .alert("No App Available", isPresented: $showsNoAppAlert) {
            Button("Copy Number") { UIPasteboard.general.string = value }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No installed app can open this number. Check Settings › Phone Numbers, or copy the number.")
        }
    }
}
