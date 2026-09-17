import SwiftUI
import UIKit

/// Shown briefly on app launch — icon, app name, and version info — while `ContentView`
/// finishes its first render. There's no slow async startup work today (the
/// `ModelContainer` is built synchronously before `ContentView` even appears, see
/// `EngelsystemClientApp`), so this is a deliberate minimum-duration branding splash
/// (`ContentView.launchScreenDuration`) rather than a gate on real work — it exists so
/// the app doesn't jump straight from the system launch screen into either
/// `InstanceSetupView` or `MainView` with no branding moment in between.
struct LaunchScreenView: View {
    var body: some View {
        VStack(spacing: 12) {
            appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(appName)
                .font(.title2)
                .fontWeight(.semibold)
            Text(AppVersionInfo.displayString)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    /// The app's own running icon, read from `Info.plist`'s `CFBundleIcons` — the
    /// standard way to show the real app icon inside SwiftUI, since an appicon asset
    /// set isn't otherwise referenceable as a plain `Image`.
    private var appIcon: Image {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last,
           let uiImage = UIImage(named: name) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "app.fill")
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Engelsystem Client"
    }
}

#Preview {
    LaunchScreenView()
}
