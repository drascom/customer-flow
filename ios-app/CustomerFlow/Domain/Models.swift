import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case doctor
    case agent
    case admin

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ConsultationStatus: String, Codable, Sendable {
    case waiting
    case answered
    case closed

    var title: String {
        switch self {
        case .waiting: "Waiting for Doctor"
        case .answered: "Waiting for Agent Confirmation"
        case .closed: "Closed"
        }
    }
}

enum DoctorQueueFilter: String, CaseIterable, Identifiable {
    case myWaiting
    case unassigned
    case answered
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myWaiting: "My Waiting"
        case .unassigned: "Unassigned"
        case .answered: "Answered"
        case .closed: "Closed"
        }
    }
}

struct Patient: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var assignedDoctorID: String?
    var lastUpdated: Date
}

struct ConsultationMessage: Identifiable, Hashable, Codable, Sendable {
    enum AuthorRole: String, Codable, Sendable { case agent, doctor, system }

    let id: UUID
    let author: String
    let role: AuthorRole
    let createdAt: Date
    let text: String
    let approximateGrafts: String?
    let recommendedPrice: String?

    init(
        id: UUID = UUID(),
        author: String,
        role: AuthorRole,
        createdAt: Date = .now,
        text: String,
        approximateGrafts: String? = nil,
        recommendedPrice: String? = nil
    ) {
        self.id = id
        self.author = author
        self.role = role
        self.createdAt = createdAt
        self.text = text
        self.approximateGrafts = approximateGrafts
        self.recommendedPrice = recommendedPrice
    }
}

struct ConsultationCase: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let reference: String
    var patient: Patient
    let agentName: String
    var assignedDoctorID: String?
    let uploadedAt: Date
    var status: ConsultationStatus
    var photoCount: Int
    var agentNote: String
    var agentGrafts: String
    var currency: String
    var agentPrice: String
    var messages: [ConsultationMessage]
}

struct PatientMatchCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let assignedDoctorName: String?
    let lastUpdated: Date
    let createdByAnotherAgent: Bool
    let photoCount: Int
}

struct DoctorRecommendation: Codable, Sendable {
    let approximateGrafts: String
    let recommendedPrice: String
    let text: String
}
