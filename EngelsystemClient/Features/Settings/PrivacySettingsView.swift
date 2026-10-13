import SwiftUI
import EngelsystemClientKit

/// Settings page "Privacy": how map links open and what the embedded map page may keep on
/// this device (ADR 0014), plus a pointer to the privacy policy.
struct PrivacySettingsView: View {
    @AppStorage(MapLinkMode.userDefaultsKey)
    private var mapLinkModeRaw: String = MapLinkMode.embedded.rawValue
    @AppStorage(MapWebsiteDataRetention.userDefaultsKey)
    private var mapDataAutoDeleteDays: Int = MapWebsiteDataRetention.defaultDays
    @State private var showsMapDataDeletion = false

    var body: some View {
        List {
            Section {
                Picker("Map Links", selection: $mapLinkModeRaw) {
                    ForEach(MapLinkMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Picker("Delete Map Data Automatically", selection: $mapDataAutoDeleteDays) {
                    ForEach(MapWebsiteDataRetention.choices, id: \.self) { days in
                        Text(MapWebsiteDataRetention.title(days: days)).tag(days)
                    }
                }
                Button("Delete Map Website Data…", role: .destructive) { showsMapDataDeletion = true }
                    .confirmationDialog("Delete Map Website Data", isPresented: $showsMapDataDeletion, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            Task { await MapWebsiteData.deleteAll() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Removes all cookies and other data the embedded map pages stored.")
                    }
            } header: {
                Text("Maps")
            } footer: {
                Text("“Link and Embedded Map” shows the map page inside a location's screen; “Link Only” just offers the link. The page is loaded from the address the server provides, every time the screen opens. Cookies the map page stores (for example your consent) are kept on this device, apart from Safari, until they are deleted automatically (every 30 days by default, or when the app quits if you choose that) or by you here. These settings are per device.")
            }

            Section {
                Link(destination: AboutSettingsView.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "safari")
                }
            } footer: {
                Text("Your API key stays in the Keychain, nothing is sent to the app's developer, and Engelsystem requests go only to the servers you add.")
            }
        }
        .navigationTitle("Privacy")
    }
}
