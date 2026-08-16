import Foundation
import UserNotifications

@MainActor
protocol CaseRepository: AnyObject {
    func fetchCases() async throws -> [ConsultationCase]
    func createCase(patientName: String, patientProfile: PatientProfileInput, agentName: String, grafts: String, currency: String, price: String, note: String, photoCount: Int, duplicateConfirmedDifferent: Bool) async throws -> ConsultationCase
    func uploadPhoto(caseID: UUID, data: Data, contentType: String) async throws -> ConsultationCase
    func deletePhoto(caseID: UUID, photoID: String) async throws -> ConsultationCase
    func fetchPhoto(photoID: String) async throws -> Data
    func sendPhotoMessage(caseID: UUID, data: Data, contentType: String, text: String) async throws -> ConsultationCase
    func fetchMessagePhoto(messageID: String) async throws -> Data
    func deleteMessage(caseID: UUID, messageID: UUID) async throws -> ConsultationCase
    func sendRecommendation(caseID: UUID, doctorID: String, recommendation: DoctorRecommendation) async throws -> ConsultationCase
    func saveAgentValues(caseID: UUID, patientName: String, patientProfile: PatientProfileInput, grafts: String, currency: String, price: String) async throws
    func confirmAndClose(caseID: UUID, finalGrafts: String, finalPrice: String) async throws
    func sendAgentUpdate(caseID: UUID, text: String) async throws
}

protocol PatientMatchingService: Sendable {
    func findMatches(for patientName: String) async throws -> [PatientMatchCandidate]
}

struct AuthenticatedSession: Sendable {
    let userID: String
    let serverAccessToken: String
    let expiresAt: Date
}

protocol OTPAuthenticationService: Sendable {
    func requestCode(for destination: String) async throws
    func verifyCode(_ code: String, for destination: String) async throws -> AuthenticatedSession
    func signOut() async throws
}

protocol NotificationService: Sendable {
    func requestAuthorization() async throws -> Bool
    func registerDeviceToken(_ token: Data) async throws
}

protocol APIClient: Sendable {
    var baseURL: URL? { get }
    func configure(baseURL: URL)
}

final class NoopNotificationService: NotificationService, @unchecked Sendable {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func registerDeviceToken(_ token: Data) async throws {
        // Firebase/APNs adapter will forward this token to the configured server.
    }
}

final class ConfigurableAPIClient: APIClient, @unchecked Sendable {
    private(set) var baseURL: URL?

    func configure(baseURL: URL) {
        self.baseURL = baseURL
    }
}
