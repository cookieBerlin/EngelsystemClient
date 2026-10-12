import Foundation
import Testing
@testable import EngelsystemClientKit

/// Covers `APIClient`'s real (non-demo) code path through `StubbedNetwork` — response
/// bodies are the demo data encoded with the generator's own encoder, so decoding is
/// exercised against realistic shapes.
extension StubbedNetworkTests {
    @Suite
    struct APIClientNetworkTests {
        private let client = APIClient()
        private let credential = StubbedNetwork.credential

        init() {
            StubbedNetwork.install()
        }

        // MARK: Plain fetches

        @Test func fetchInfoDecodesTheData() async throws {
            try StubURLProtocol.route("GET /info", data: DemoData.info)
            let info = try await client.fetchInfo(credential)
            #expect(info.name == DemoData.info.name)
        }

        @Test func fetchInfoWithoutDataIsADecodingError() async {
            StubURLProtocol.route("GET /info", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in /info response")) {
                try await client.fetchInfo(credential)
            }
        }

        @Test func requestsCarryTheAPIKeyHeaderAndBaseURL() async throws {
            try StubURLProtocol.route("GET /info", data: DemoData.info)
            _ = try await client.fetchInfo(credential)
            let request = try #require(StubURLProtocol.recorded.first)
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret-key")
            #expect(request.url?.host == "stub.test")
        }

        @Test func fetchNewsAndAngelTypesAndLocationsAndShiftTypesDecodeLists() async throws {
            try StubURLProtocol.route("GET /news", data: DemoData.news)
            try StubURLProtocol.route("GET /angeltypes", data: DemoData.angelTypes)
            try StubURLProtocol.route("GET /locations", data: DemoData.locations)
            try StubURLProtocol.route("GET /shifttypes", data: DemoData.shiftTypes)
            #expect(try await client.fetchNews(credential).count == DemoData.news.count)
            #expect(try await client.fetchAngelTypes(credential).count == DemoData.angelTypes.count)
            #expect(try await client.fetchLocations(credential).count == DemoData.locations.count)
            #expect(try await client.fetchShiftTypes(credential).count == DemoData.shiftTypes.count)
        }

        /// COMPAT(#1709): "Test Connection" warns when data requests are denied, but never otherwise.
        @Test func accessProbeWarnsOnlyOnForbidden() async throws {
            StubURLProtocol.route("GET /users/self", status: 403)
            #expect(await client.accessDeniedWarning(credential) == APIError.missingPrivilegeMessage)
            StubURLProtocol.route("GET /users/self", status: 500)
            #expect(await client.accessDeniedWarning(credential) == nil)
            try StubURLProtocol.route("GET /users/self", data: DemoData.ownProfile)
            #expect(await client.accessDeniedWarning(credential) == nil)
            let demo = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
            #expect(await client.accessDeniedWarning(demo) == nil)
        }

        @Test func theForbiddenMessageNamesThePrivilegeAndGroupsButNoPullRequest() {
            let message = APIError.forbidden.userMessage
            #expect(message == APIError.missingPrivilegeMessage)
            #expect(message.contains("API") && message.contains("Bureaucrat") && message.contains("privilege"))
            #expect(!message.lowercased().contains("pull request"))
        }

        /// COMPAT(#1710): a server without PR #1710 omits `comments_count` — the list must still decode.
        @Test func newsWithoutCommentsCountStillDecodesAndCachesZero() async throws {
            let json = """
            {"data":[{"id":1,"name":"Hello","text":"Body","is_meeting":false,"is_pinned":false,\
            "is_highlighted":false,"created_at":"2026-10-01T10:00:00+00:00","updated_at":null,\
            "url":"https://example.org/news/1"}]}
            """
            StubURLProtocol.route("GET /news", body: Data(json.utf8))
            let news = try await client.fetchNews(credential)
            #expect(news.count == 1)
            #expect(news[0].commentsCount == nil)
            let cached = CachedNews(news: news[0], instanceID: UUID())
            #expect(cached.commentsCount == 0)
            cached.commentsCount = 5
            cached.apply(news[0])
            #expect(cached.commentsCount == 0)
        }

        @Test func userScopedListsUseTheUserReferenceInThePath() async throws {
            try StubURLProtocol.route("GET /users/self/shifts", data: DemoData.shifts)
            try StubURLProtocol.route("GET /users/self/worklogs", data: DemoData.worklogs)
            try StubURLProtocol.route("GET /users/7/angeltypes", data: DemoData.ownAngelTypes)
            #expect(try await client.fetchShifts(for: .me, credential).count == DemoData.shifts.count)
            #expect(try await client.fetchWorklogs(for: .me, credential).count == DemoData.worklogs.count)
            #expect(try await client.fetchOwnAngelTypes(for: .id(7), credential).count == DemoData.ownAngelTypes.count)
        }

        @Test func fetchUsersAndOwnProfileDecode() async throws {
            try StubURLProtocol.route("GET /users", data: DemoData.users)
            try StubURLProtocol.route("GET /users/self", data: DemoData.ownProfile)
            #expect(try await client.fetchUsers(credential).count == DemoData.users.count)
            let profile = try await client.fetchOwnProfile(for: .me, credential)
            #expect(profile.name == DemoData.ownProfile.name)
        }

        @Test func fetchOwnProfileWithoutDataIsADecodingError() async {
            StubURLProtocol.route("GET /users/self", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in /users/{id} response")) {
                try await client.fetchOwnProfile(for: .me, credential)
            }
        }

        // MARK: List endpoints treat an empty body and a 404 as an empty list

        @Test func aListWithoutADataFieldIsEmpty() async throws {
            StubURLProtocol.route("GET /news", body: Data("{}".utf8))
            #expect(try await client.fetchNews(credential).isEmpty)
        }

        @Test func everyListEndpointTreatsAMissingDataFieldAsEmpty() async throws {
            for path in ["/angeltypes", "/users/self/angeltypes", "/locations", "/shifttypes",
                         "/users/self/shifts", "/users/self/worklogs", "/users"] {
                StubURLProtocol.route("GET \(path)", body: Data("{}".utf8))
            }
            #expect(try await client.fetchAngelTypes(credential).isEmpty)
            #expect(try await client.fetchOwnAngelTypes(for: .me, credential).isEmpty)
            #expect(try await client.fetchLocations(credential).isEmpty)
            #expect(try await client.fetchShiftTypes(credential).isEmpty)
            #expect(try await client.fetchShifts(for: .me, credential).isEmpty)
            #expect(try await client.fetchWorklogs(for: .me, credential).isEmpty)
            #expect(try await client.fetchUsers(credential).isEmpty)
        }

        @Test func concurrentRequestsAreSerializedByTheGate() async throws {
            try StubURLProtocol.route("GET /info", data: DemoData.info)
            StubURLProtocol.route("GET /news", body: Data(#"{"data":[]}"#.utf8), delay: 0.15)
            let client = self.client
            let credential = self.credential
            async let slow = client.fetchNews(credential)
            async let second = client.fetchInfo(credential)
            async let third = client.fetchNews(credential)
            let results = try await (slow, second, third)
            #expect(results.0.isEmpty && results.2.isEmpty)
            #expect(results.1.name == DemoData.info.name)
            #expect(StubURLProtocol.recorded.count == 3)
        }

        @Test func aListEndpointThatAnswers404IsEmpty() async throws {
            StubURLProtocol.route("GET /locations", status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
            #expect(try await client.fetchLocations(credential).isEmpty)
        }

        // MARK: Single-resource endpoints

        @Test func fetchNewsDetailAndLocationDecode() async throws {
            let detail = try #require(DemoData.newsDetail(id: DemoData.news[0].id))
            let location = try #require(DemoData.locations.first)
            try StubURLProtocol.route("GET /news/\(detail.id)", data: detail)
            try StubURLProtocol.route("GET /locations/\(location.id)", data: location)
            #expect(try await client.fetchNewsDetail(id: detail.id, credential).id == detail.id)
            #expect(try await client.fetchLocation(id: location.id, credential).id == location.id)
        }

        @Test func singleResourcesWithoutDataAreDecodingErrors() async {
            StubURLProtocol.route("GET /news/1", body: Data("{}".utf8))
            StubURLProtocol.route("GET /locations/1", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in /news/{id} response")) {
                try await client.fetchNewsDetail(id: 1, credential)
            }
            await #expect(throws: APIError.decoding("Missing data in /locations/{id} response")) {
                try await client.fetchLocation(id: 1, credential)
            }
        }

        @Test func aSingleResourceThatAnswers404IsNotFoundNotEmpty() async {
            StubURLProtocol.route("GET /news/9", status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
            await #expect(throws: APIError.notFound) {
                try await client.fetchNewsDetail(id: 9, credential)
            }
        }

        // MARK: Error mapping

        @Test func statusCodesMapToAPIErrors() async {
            StubURLProtocol.route("GET /info", status: 401)
            await #expect(throws: APIError.unauthorized) { try await client.fetchInfo(credential) }
            StubURLProtocol.route("GET /info", status: 403)
            await #expect(throws: APIError.forbidden) { try await client.fetchInfo(credential) }
            StubURLProtocol.route("GET /info", status: 500)
            await #expect(throws: APIError.server(statusCode: 500)) { try await client.fetchInfo(credential) }
        }

        @Test func anInvalidBaseURLFailsBeforeAnyRequest() async {
            let bad = EventCredential(baseURL: "", apiKey: "k")
            await #expect(throws: APIError.invalidBaseURL) { try await client.fetchInfo(bad) }
            #expect(StubURLProtocol.recorded.isEmpty)
        }

        @Test func cancellationIsRethrownAsIsNotWrapped() async {
            try? StubURLProtocol.route("GET /info", data: DemoData.info)
            let client = self.client
            let credential = self.credential
            let task = Task {
                while !Task.isCancelled { await Task.yield() }
                return try await client.fetchInfo(credential)
            }
            task.cancel()
            do {
                _ = try await task.value
                Issue.record("expected cancellation")
            } catch {
                #expect(error is CancellationError)
            }
        }

        // MARK: Self-reference probe

        @Test func selfProbeReportsWorkingAndBrokenServers() async throws {
            try StubURLProtocol.route("GET /users/self/worklogs", data: DemoData.worklogs)
            #expect(await client.selfUserReferenceWorks(credential))
            StubURLProtocol.route("GET /users/self/worklogs", status: 404)
            #expect(await client.selfUserReferenceWorks(credential) == false)
        }

        // MARK: Messages

        @Test func conversationsAndMessagesDecode() async throws {
            let conversations = await DemoData.conversations()
            let messages = await DemoData.conversation(otherUserID: conversations[0].otherUser.id)
            try StubURLProtocol.route("GET /messages", data: conversations)
            StubURLProtocol.route(
                "GET /messages/5",
                body: Data("{\"data\":{\"messages\":".utf8) + (try CodableHelper.jsonEncoder.encode(messages)) + Data("}}".utf8)
            )
            #expect(try await client.fetchConversations(credential).count == conversations.count)
            #expect(try await client.fetchConversation(otherUserID: 5, credential).count == messages.count)
        }

        @Test func aConversationWithoutDataIsADecodingErrorAndWithoutMessagesIsEmpty() async throws {
            StubURLProtocol.route("GET /messages/5", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in /messages/{id} response")) {
                try await client.fetchConversation(otherUserID: 5, credential)
            }
            StubURLProtocol.route("GET /messages/5", body: Data(#"{"data":{}}"#.utf8))
            #expect(try await client.fetchConversation(otherUserID: 5, credential).isEmpty)
        }

        @Test func fetchConversationsWithoutDataIsEmpty() async throws {
            StubURLProtocol.route("GET /messages", body: Data("{}".utf8))
            #expect(try await client.fetchConversations(credential).isEmpty)
        }

        @Test func sendMessagePostsTheTextAndDecodesTheCreatedMessage() async throws {
            let created = await DemoData.conversations()[0].latestMessage
            try StubURLProtocol.route("POST /messages/5", status: 201, data: created)
            let message = try await client.sendMessage(to: 5, text: "hello", credential)
            #expect(message.text == created.text)
            let request = try #require(StubURLProtocol.recorded.last)
            #expect(request.httpMethod == "POST")
        }

        @Test func sendMessageWithoutDataIsADecodingError() async {
            StubURLProtocol.route("POST /messages/5", status: 201, body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in POST /messages/{id} response")) {
                try await client.sendMessage(to: 5, text: "x", credential)
            }
        }

        @Test func deleteMessageSucceedsOn204AndMapsForbidden() async throws {
            StubURLProtocol.route("DELETE /messages/3", status: 204, body: Data())
            try await client.deleteMessage(id: 3, credential)
            StubURLProtocol.route("DELETE /messages/3", status: 403)
            await #expect(throws: APIError.forbidden) { try await client.deleteMessage(id: 3, credential) }
        }

        @Test func setMessageReadPatchesAndDecodes() async throws {
            let created = await DemoData.conversations()[0].latestMessage
            try StubURLProtocol.route("PATCH /messages/3", data: created)
            let message = try await client.setMessageRead(id: 3, read: true, credential)
            #expect(message.id == created.id)
            StubURLProtocol.route("PATCH /messages/3", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in PATCH /messages/{msgId} response")) {
                try await client.setMessageRead(id: 3, read: true, credential)
            }
        }

        // MARK: Messages capability probe

        @Test func messagesSupportedProbeInterpretsTheServersAnswers() async throws {
            try StubURLProtocol.route("GET /messages", data: [Conversation]())
            #expect(await client.messagesSupported(credential))

            StubURLProtocol.route("GET /messages", status: 404, body: Data(#"{"message":"Not implemented"}"#.utf8))
            #expect(await client.messagesSupported(credential) == false)

            StubURLProtocol.route("GET /messages", status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
            #expect(await client.messagesSupported(credential))
        }

        @Test func messagesSupportedProbeAssumesSupportForAnInvalidBaseURL() async {
            #expect(await client.messagesSupported(EventCredential(baseURL: "", apiKey: "k")))
        }
    }
}
