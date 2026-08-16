import Foundation
import Security

struct AuthenticatedUser: Codable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let role: UserRole
    let agencyID: String?
    let email: String?
    let phone: String?
}

struct ServerSession: Codable, Sendable {
    let token: String
    let expiresAt: Date
    let user: AuthenticatedUser
}

struct ServerHealth: Codable, Sendable {
    let status: String
    let apiVersion: String
    let service: String
    let capabilities: [String]
}

struct LiveUpdateEvent: Codable, Sendable {
    let kind: String
    let entityID: String?
    let actorID: String
    let occurredAt: Date
}

struct LiveUpdateResponse: Codable, Sendable {
    let revision: Int
    let changed: Bool
    let event: LiveUpdateEvent?
}

enum RemoteServiceError: LocalizedError {
    case invalidServerAddress
    case insecureServerAddress
    case incompatibleServer
    case invalidResponse
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress: "Enter a valid server address."
        case .insecureServerAddress: "This server must use a secure HTTPS address."
        case .incompatibleServer: "This server is not compatible with Customer Flow API v1."
        case .invalidResponse: "The server returned an invalid response."
        case .server(let message): message
        }
    }
}

actor RemoteAPIClient {
    let baseURL: URL
    private var accessToken: String?

    init(baseURL: URL, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.accessToken = accessToken
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func health() async throws -> ServerHealth {
        let health: ServerHealth = try await get("health")
        guard health.status == "ok", health.apiVersion == "v1" else {
            throw RemoteServiceError.incompatibleServer
        }
        return health
    }

    func login(username: String, password: String) async throws -> ServerSession {
        struct LoginBody: Encodable, Sendable { let username: String; let password: String }
        let session: ServerSession = try await send("POST", path: "auth/login", body: LoginBody(username: username, password: password))
        accessToken = session.token
        return session
    }

    func restoreSession() async throws -> AuthenticatedUser {
        struct Envelope: Decodable, Sendable { let user: AuthenticatedUser }
        let envelope: Envelope = try await get("auth/me")
        return envelope.user
    }

    func waitForChanges(since revision: Int) async throws -> LiveUpdateResponse {
        try await request(
            method: "GET",
            path: "events?since=\(revision)",
            body: nil,
            timeoutInterval: 25
        )
    }

    func fetchNotifications() async throws -> NotificationInbox {
        try await get("notifications?limit=50")
    }

    func markNotificationsRead(_ notificationIDs: [String]) async throws {
        struct Body: Encodable, Sendable { let notificationIDs: [String] }
        struct Response: Decodable, Sendable { let ok: Bool; let updatedCount: Int }
        let _: Response = try await send(
            "POST", path: "notifications/read", body: Body(notificationIDs: notificationIDs)
        )
    }

    func markAllNotificationsRead() async throws {
        struct Body: Encodable, Sendable { let all: Bool }
        struct Response: Decodable, Sendable { let ok: Bool; let updatedCount: Int }
        let _: Response = try await send("POST", path: "notifications/read", body: Body(all: true))
    }

    func registerNotificationDevice(token: String, environment: String) async throws {
        struct Body: Encodable, Sendable {
            let token: String
            let platform: String
            let environment: String
        }
        struct Device: Decodable, Sendable { let registered: Bool }
        struct Response: Decodable, Sendable { let device: Device }
        let _: Response = try await send(
            "POST", path: "notification-devices",
            body: Body(token: token, platform: "ios", environment: environment)
        )
    }

    func unregisterNotificationDevice(token: String) async throws {
        struct Body: Encodable, Sendable { let token: String }
        struct Response: Decodable, Sendable { let ok: Bool; let removed: Bool }
        let _: Response = try await send(
            "POST", path: "notification-devices/unregister", body: Body(token: token)
        )
    }

    func updateProfile(displayName: String, email: String, phone: String) async throws -> AuthenticatedUser {
        struct Body: Encodable, Sendable { let displayName: String; let email: String; let phone: String }
        struct Envelope: Decodable, Sendable { let user: AuthenticatedUser }
        let envelope: Envelope = try await send("PATCH", path: "auth/profile", body: Body(
            displayName: displayName, email: email, phone: phone
        ))
        return envelope.user
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        struct Body: Encodable, Sendable { let currentPassword: String; let newPassword: String }
        struct Response: Decodable, Sendable { let ok: Bool }
        let _: Response = try await send("POST", path: "auth/change-password", body: Body(
            currentPassword: currentPassword, newPassword: newPassword
        ))
    }

    func requestPasswordReset(identifier: String) async throws -> String {
        struct Body: Encodable, Sendable { let identifier: String }
        struct Response: Decodable, Sendable { let ok: Bool; let message: String }
        let response: Response = try await send("POST", path: "auth/password-reset/request", body: Body(identifier: identifier))
        return response.message
    }

    func resetPassword(identifier: String, code: String, newPassword: String) async throws {
        struct Body: Encodable, Sendable { let identifier: String; let code: String; let newPassword: String }
        struct Response: Decodable, Sendable { let ok: Bool }
        let _: Response = try await send("POST", path: "auth/password-reset/confirm", body: Body(
            identifier: identifier, code: code, newPassword: newPassword
        ))
    }

    func logout() async {
        struct Empty: Encodable, Sendable {}
        struct Response: Decodable, Sendable { let ok: Bool }
        let _: Response? = try? await send("POST", path: "auth/logout", body: Empty())
        accessToken = nil
    }

    func get<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        try await request(method: "GET", path: path, body: nil)
    }

    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String,
        path: String,
        body: Body
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await request(method: method, path: path, body: try encoder.encode(body))
    }

    func upload<Response: Decodable & Sendable>(
        path: String,
        data: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) async throws -> Response {
        try await request(
            method: "POST", path: path, body: data, contentType: contentType, headers: headers
        )
    }

    func download(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteServiceError.invalidServerAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw RemoteServiceError.server(message: envelope.error.message)
            }
            throw RemoteServiceError.server(message: "Server request failed (\(http.statusCode)).")
        }
        return data
    }

    private func request<Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Data?,
        contentType: String = "application/json",
        timeoutInterval: TimeInterval = 20,
        headers: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteServiceError.invalidServerAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw RemoteServiceError.server(message: envelope.error.message)
            }
            throw RemoteServiceError.server(message: "Server request failed (\(http.statusCode)).")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw RemoteServiceError.invalidResponse }
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

@MainActor
final class RemoteCaseRepository: CaseRepository {
    private let client: RemoteAPIClient

    init(client: RemoteAPIClient) { self.client = client }

    func fetchCases() async throws -> [ConsultationCase] {
        struct Envelope: Decodable, Sendable { let cases: [ConsultationCase] }
        let envelope: Envelope = try await client.get("cases")
        return envelope.cases
    }

    func createCase(patientName: String, patientProfile: PatientProfileInput, agentName: String, grafts: String, currency: String, price: String,
                    note: String, photoCount: Int, duplicateConfirmedDifferent: Bool) async throws -> ConsultationCase {
        struct Body: Encodable, Sendable {
            let patientName: String
            let patientProfile: PatientProfileInput
            let grafts: String
            let currency: String
            let price: String
            let note: String
            let photoCount: Int
            let duplicateConfirmedDifferent: Bool
        }
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let envelope: Envelope = try await client.send("POST", path: "cases", body: Body(
            patientName: patientName, patientProfile: patientProfile, grafts: grafts, currency: currency, price: price,
            note: note, photoCount: photoCount, duplicateConfirmedDifferent: duplicateConfirmedDifferent
        ))
        return envelope.case
    }

    func uploadPhoto(caseID: UUID, data: Data, contentType: String) async throws -> ConsultationCase {
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let envelope: Envelope = try await client.upload(
            path: "cases/\(caseID)/photos", data: data, contentType: contentType
        )
        return envelope.case
    }

    func deletePhoto(caseID: UUID, photoID: String) async throws -> ConsultationCase {
        struct Empty: Encodable, Sendable {}
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let envelope: Envelope = try await client.send(
            "DELETE", path: "cases/\(caseID)/photos/\(photoID)", body: Empty()
        )
        return envelope.case
    }

    func fetchPhoto(photoID: String) async throws -> Data {
        try await client.download("photos/\(photoID)")
    }

    func sendPhotoMessage(
        caseID: UUID, data: Data, contentType: String, text: String
    ) async throws -> ConsultationCase {
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let encodedText = Data(text.utf8).base64EncodedString()
        let envelope: Envelope = try await client.upload(
            path: "cases/\(caseID)/message-photos",
            data: data,
            contentType: contentType,
            headers: encodedText.isEmpty ? [:] : ["X-Message-Text": encodedText]
        )
        return envelope.case
    }

    func fetchMessagePhoto(messageID: String) async throws -> Data {
        try await client.download("message-photos/\(messageID)")
    }

    func deleteMessage(caseID: UUID, messageID: UUID) async throws -> ConsultationCase {
        struct Empty: Encodable, Sendable {}
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let envelope: Envelope = try await client.send(
            "DELETE", path: "cases/\(caseID)/messages/\(messageID)", body: Empty()
        )
        return envelope.case
    }

    func sendRecommendation(caseID: UUID, doctorID: String, recommendation: DoctorRecommendation) async throws -> ConsultationCase {
        struct Body: Encodable, Sendable {
            let approximateGrafts: String?
            let recommendedPrice: String?
            let text: String
        }
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let envelope: Envelope = try await client.send("POST", path: "cases/\(caseID)/doctor-messages", body: Body(
            approximateGrafts: recommendation.approximateGrafts,
            recommendedPrice: recommendation.recommendedPrice,
            text: recommendation.text
        ))
        return envelope.case
    }

    func saveAgentValues(caseID: UUID, patientName: String, patientProfile: PatientProfileInput, grafts: String, currency: String, price: String) async throws {
        struct Body: Encodable, Sendable {
            let patientName: String
            let patientProfile: PatientProfileInput
            let grafts: String
            let currency: String
            let price: String
        }
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let _: Envelope = try await client.send("PATCH", path: "cases/\(caseID)/agent-values",
                                                body: Body(patientName: patientName, patientProfile: patientProfile,
                                                           grafts: grafts, currency: currency, price: price))
    }

    func confirmAndClose(caseID: UUID, finalGrafts: String, finalPrice: String) async throws {
        struct Body: Encodable, Sendable { let finalGrafts: String; let finalPrice: String }
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let _: Envelope = try await client.send(
            "POST", path: "cases/\(caseID)/close",
            body: Body(finalGrafts: finalGrafts, finalPrice: finalPrice)
        )
    }

    func sendAgentUpdate(caseID: UUID, text: String) async throws {
        struct Body: Encodable, Sendable { let text: String }
        struct Envelope: Decodable, Sendable { let `case`: ConsultationCase }
        let _: Envelope = try await client.send("POST", path: "cases/\(caseID)/agent-updates", body: Body(text: text))
    }
}

struct RemotePatientMatchingService: PatientMatchingService {
    let client: RemoteAPIClient

    func findMatches(for patientName: String) async throws -> [PatientMatchCandidate] {
        struct Envelope: Decodable, Sendable { let matches: [PatientMatchCandidate] }
        var components = URLComponents()
        components.path = "patients/matches"
        components.queryItems = [URLQueryItem(name: "name", value: patientName)]
        let path = components.string ?? "patients/matches"
        let envelope: Envelope = try await client.get(path)
        return envelope.matches
    }
}

enum ServerAddress {
    static func normalize(_ input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard var components = URLComponents(string: value), components.host != nil else {
            throw RemoteServiceError.invalidServerAddress
        }
#if !DEBUG
        guard components.scheme?.lowercased() == "https" else { throw RemoteServiceError.insecureServerAddress }
#endif
        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { path = "api/v1" }
        if path != "api/v1" { throw RemoteServiceError.incompatibleServer }
        components.path = "/" + path + "/"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw RemoteServiceError.invalidServerAddress }
        return url
    }
}

enum SecureTokenStore {
    private static let service = "com.customerflow.client.session"
    private static let account = "server-access-token"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw RemoteServiceError.server(message: "The secure session could not be saved on this device.")
        }
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
