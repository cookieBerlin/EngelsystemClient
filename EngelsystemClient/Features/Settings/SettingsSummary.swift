import Foundation
import EngelsystemClientKit

extension SettingsSummary {
    /// The privacy page's summary: how map links are shown (the map mode lives in the app target).
    static func privacy(mapLinkRaw: String) -> String {
        MapLinkMode.stored(raw: mapLinkRaw) == .embedded ? "Embedded map" : "Link only"
    }
}
