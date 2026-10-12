import CloudKit
import Foundation
import Testing
@testable import EngelsystemClientKit

struct ICloudAvailabilityTests {
    private struct Boom: Error {}

    @Test func isAvailableMirrorsTheUbiquityIdentityToken() {
        #expect(ICloudAvailability.isAvailable == (FileManager.default.ubiquityIdentityToken != nil))
    }

    @Test func statusMessageNamesBothChecks() {
        let message = ICloudAvailability.statusMessage(isAvailable: false, status: .available)
        #expect(message.contains("ubiquityIdentityToken != nil = false"))
        #expect(message.contains("CKContainer.accountStatus = "))
    }

    @Test func failureMessageIncludesTheError() {
        let message = ICloudAvailability.failureMessage(isAvailable: true, error: Boom())
        #expect(message.contains("ubiquityIdentityToken != nil = true"))
        #expect(message.contains("threw:"))
    }

    @Test func logCloudKitAccountStatusAsksTheContainerForItsStatus() async {
        let asked = Box()
        await ICloudAvailability.logCloudKitAccountStatus(containerIdentifier: "iCloud.test") { identifier in
            await asked.record(identifier)
            return .available
        }.value
        #expect(await asked.value == "iCloud.test")
    }

    @Test func logCloudKitAccountStatusSurvivesAThrowingContainer() async {
        await ICloudAvailability.logCloudKitAccountStatus(containerIdentifier: "iCloud.test") { _ in
            throw Boom()
        }.value
    }

    private actor Box {
        var value: String?
        func record(_ v: String) { value = v }
    }
}
