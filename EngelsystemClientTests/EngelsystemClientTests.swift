//
//  EngelsystemClientTests.swift
//  EngelsystemClientTests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

struct SyncErrorMapperTests {
    @Test func isUnauthorizedIsTrueOnlyForAPIErrorUnauthorized() {
        #expect(SyncErrorMapper.isUnauthorized(APIError.unauthorized))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.forbidden))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.notFound))
        #expect(!SyncErrorMapper.isUnauthorized(InstanceCredentialError.apiKeyNotFound))
    }

    @Test func messageMapsInstanceCredentialAndKeychainErrorsToReadableText() {
        #expect(SyncErrorMapper.message(for: InstanceCredentialError.apiKeyNotFound).contains("Settings"))
        #expect(SyncErrorMapper.message(for: KeychainError.unexpectedData).contains("keychain"))
        #expect(SyncErrorMapper.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
    }
}
