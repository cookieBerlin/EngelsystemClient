#!/bin/bash

# EngelsystemClientKit Package Setup Script
# Creates the complete package structure with all files

set -e  # Abort on error

echo "🚀 Starting EngelsystemClientKit package setup..."

# Base directory
BASE_DIR="/path/to/EngelsystemClient"
PACKAGE_DIR="$BASE_DIR/EngelsystemClientKit"

cd "$BASE_DIR"

echo ""
echo "📂 Creating directory structure..."
mkdir -p "$PACKAGE_DIR/Sources/EngelsystemClientKit/Persistence"
mkdir -p "$PACKAGE_DIR/Tests/EngelsystemClientKitTests"

echo "  ✓ $PACKAGE_DIR/Sources/EngelsystemClientKit/Persistence"
echo "  ✓ $PACKAGE_DIR/Tests/EngelsystemClientKitTests"

echo ""
echo "📝 Creating Package.swift..."

cat > "$PACKAGE_DIR/Package.swift" << 'PACKAGE_EOF'
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EngelsystemClientKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "EngelsystemClientKit",
            targets: ["EngelsystemClientKit"]
        )
    ],
    dependencies: [
        // Room for future dependencies, e.g. if the generated
        // OpenAPI client should be pulled in as a separate package
        // instead of as source code.
    ],
    targets: [
        .target(
            name: "EngelsystemClientKit",
            path: "Sources/EngelsystemClientKit"
        ),
        .testTarget(
            name: "EngelsystemClientKitTests",
            dependencies: ["EngelsystemClientKit"],
            path: "Tests/EngelsystemClientKitTests"
        )
    ]
)
PACKAGE_EOF

echo "  ✓ Package.swift created"

echo ""
echo "📝 Creating Instance.swift..."

cat > "$PACKAGE_DIR/Sources/EngelsystemClientKit/Persistence/Instance.swift" << 'INSTANCE_EOF'
//
//  Instance.swift
//  EngelsystemClientKit
//
//  Created on 01.09.2026.
//

import Foundation
import SwiftData

/// Represents an Engelsystem instance (server/event).
/// Multi-instance capable: users can manage multiple events/servers at once.
@Model
public final class Instance {
    /// Unique ID of the instance
    @Attribute(.unique) public var id: UUID

    /// User-friendly name (e.g. "37C3", "Chaos Communication Congress 2026")
    public var name: String

    /// Base URL of the Engelsystem server (e.g. "https://events.ccc.de/congress/2026/engelsystem")
    public var baseURL: String

    /// Reference to the keychain entry for the API key.
    /// Stores not the key itself, only the reference/ID used to look it up in the keychain.
    /// The actual API key is stored in the iCloud-synced keychain.
    public var apiKeyKeychainRef: String

    /// Time the instance was created
    public var createdAt: Date

    /// Time of the last update
    public var updatedAt: Date

    /// Relationship to all cache objects (shifts, news, etc.)
    /// These are deleted automatically when the instance is deleted (.cascade)
    @Relationship(deleteRule: .cascade, inverse: \CachedShift.instance)
    public var cachedShifts: [CachedShift]?

    /// Initializer
    /// - Parameters:
    ///   - id: Unique ID (generated automatically)
    ///   - name: User-friendly name of the instance
    ///   - baseURL: Base URL of the Engelsystem server
    ///   - apiKeyKeychainRef: Reference to the keychain entry for the API key
    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKeyKeychainRef: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cachedShifts = []
    }
}

// MARK: - Convenience Extensions

public extension Instance {
    /// Updates the timestamp of the last change
    func touch() {
        self.updatedAt = Date()
    }

    /// Normalized base URL (removes trailing slashes)
    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Full API base path (baseURL + /api/v0-beta)
    var apiBasePath: String {
        "\(normalizedBaseURL)/api/v0-beta"
    }
}
INSTANCE_EOF

echo "  ✓ Instance.swift created"

echo ""
echo "📝 Creating CachedShift.swift..."

cat > "$PACKAGE_DIR/Sources/EngelsystemClientKit/Persistence/CachedShift.swift" << 'CACHEDSHIFT_EOF'
//
//  CachedShift.swift
//  EngelsystemClientKit
//
//  Created on 01.09.2026.
//

import Foundation
import SwiftData

/// Cached shift data of an Engelsystem instance.
/// Persisted locally and synced between iOS/watchOS via CloudKit.
@Model
public final class CachedShift {
    /// Unique ID of the shift (from the server)
    @Attribute(.unique) public var id: Int

    /// ID of the associated instance
    public var instanceID: UUID

    /// Title/name of the shift
    public var title: String

    /// Start time of the shift
    public var startsAt: Date

    /// End time of the shift
    public var endsAt: Date

    /// Location of the shift (e.g. "Heaven", "Sendezentrum")
    public var location: String?

    /// Type of the shift (e.g. "Engel", "Shift Coordinator")
    public var shiftType: String?

    /// Angel type (e.g. "Heaven", "InfoDesk")
    public var angelType: String?

    /// Description/comment for the shift
    public var shiftDescription: String?

    /// Time of the last cache update
    public var cachedAt: Date

    /// Relationship to the parent instance
    @Relationship public var instance: Instance?

    /// Initializer
    /// - Parameters:
    ///   - id: ID of the shift (from the server)
    ///   - instanceID: ID of the associated instance
    ///   - title: Title/name of the shift
    ///   - startsAt: Start time
    ///   - endsAt: End time
    ///   - location: Location of the shift
    ///   - shiftType: Type of the shift
    ///   - angelType: Angel type
    ///   - shiftDescription: Description
    public init(
        id: Int,
        instanceID: UUID,
        title: String,
        startsAt: Date,
        endsAt: Date,
        location: String? = nil,
        shiftType: String? = nil,
        angelType: String? = nil,
        shiftDescription: String? = nil
    ) {
        self.id = id
        self.instanceID = instanceID
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = location
        self.shiftType = shiftType
        self.angelType = angelType
        self.shiftDescription = shiftDescription
        self.cachedAt = Date()
    }
}

// MARK: - Convenience Extensions

public extension CachedShift {
    /// Duration of the shift in seconds
    var duration: TimeInterval {
        endsAt.timeIntervalSince(startsAt)
    }

    /// Duration of the shift in hours (rounded)
    var durationInHours: Double {
        duration / 3600.0
    }

    /// Whether the shift is in the future
    var isFuture: Bool {
        startsAt > Date()
    }

    /// Whether the shift is currently ongoing
    var isOngoing: Bool {
        let now = Date()
        return startsAt <= now && now <= endsAt
    }

    /// Whether the shift is already over
    var isPast: Bool {
        endsAt < Date()
    }

    /// Time for a local notification (e.g. 15 minutes before shift start)
    /// - Parameter minutesBefore: Number of minutes before shift start
    /// - Returns: Date for the notification, or nil if the shift is already over
    func notificationDate(minutesBefore: Int = 15) -> Date? {
        let notificationDate = startsAt.addingTimeInterval(-TimeInterval(minutesBefore * 60))
        return notificationDate > Date() ? notificationDate : nil
    }

    /// Formatted string for the time range (e.g. "14:00 - 18:00")
    func formattedTimeRange() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let start = formatter.string(from: startsAt)
        let end = formatter.string(from: endsAt)
        return "\(start) - \(end)"
    }

    /// Updates the cache timestamp
    func updateCacheTimestamp() {
        self.cachedAt = Date()
    }
}

// MARK: - Sorting

public extension CachedShift {
    /// Compares two shifts by start time
    static func sortedByStartTime(_ shifts: [CachedShift]) -> [CachedShift] {
        shifts.sorted { $0.startsAt < $1.startsAt }
    }

    /// Filters upcoming shifts and sorts them by start time
    static func upcomingShifts(from shifts: [CachedShift]) -> [CachedShift] {
        shifts.filter { $0.isFuture }.sorted { $0.startsAt < $1.startsAt }
    }

    /// Returns the next upcoming shift (for the Watch app)
    static func nextShift(from shifts: [CachedShift]) -> CachedShift? {
        upcomingShifts(from: shifts).first
    }
}
CACHEDSHIFT_EOF

echo "  ✓ CachedShift.swift created"

echo ""
echo "🗑️  Cleaning up old duplicates..."

# Remove old duplicates
rm -f "$BASE_DIR/Package.swift"
rm -f "$BASE_DIR/CachedShift.swift"
rm -f "$BASE_DIR/Instance.swift"
rm -f "$BASE_DIR/SourcesEngelsystemClientKitPersistence"*.swift
rm -f "$BASE_DIR/EngelsystemClientKitSourcesEngelsystemClientKitPersistence"*.swift

echo "  ✓ Duplicates removed"

echo ""
echo "✅ Setup complete!"
echo ""
echo "📁 Package structure:"
tree -L 4 "$PACKAGE_DIR" 2>/dev/null || find "$PACKAGE_DIR" -type f -o -type d | head -20
echo ""
echo "🔨 Next steps in Xcode:"
echo "   1. Close the project (File → Close Project)"
echo "   2. Reopen the project"
echo "   3. Select the project → Target 'EngelsystemClient' → General"
echo "   4. Frameworks, Libraries → '+' → Add Other → Add Local Package"
echo "   5. Choose the folder: EngelsystemClientKit"
echo "   6. Repeat for the Watch target"
echo "   7. ⌘+Shift+K (Clean) → ⌘+B (Build)"
echo ""
echo "🎉 Done!"
