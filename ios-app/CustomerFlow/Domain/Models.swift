import Foundation

enum AppCurrency {
    static let code = "GBP"
    static let symbol = "£"

    static func amount(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["GBP ", "EUR "] where cleaned.hasPrefix(prefix) {
            cleaned.removeFirst(prefix.count)
        }
        if cleaned.hasPrefix("£") || cleaned.hasPrefix("€") {
            cleaned.removeFirst()
        }
        return "\(symbol)\(cleaned.trimmingCharacters(in: .whitespaces))"
    }
}

enum UserRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case doctor
    case agent
    case admin
    case manager

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
        case .closed: "Confirmed"
        }
    }
}

enum DoctorQueueFilter: String, CaseIterable, Identifiable {
    case waiting
    case answered
    case confirmed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .answered: "Answered"
        case .confirmed: "Confirmed"
        }
    }
}

struct Patient: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var dateOfBirth: String? = nil
    var gender: String? = nil
    var phone: String? = nil
    var email: String? = nil
    var address: String? = nil
    var occupation: String? = nil
    var profileNote: String? = nil
    var assignedDoctorID: String?
    var lastUpdated: Date

    var age: Int? {
        guard let dateOfBirth else { return nil }
        let components = dateOfBirth.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let birthday = calendar.date(from: DateComponents(
            year: components[0], month: components[1], day: components[2]
        )) else { return nil }
        return calendar.dateComponents([.year], from: birthday, to: .now).year
    }

    var genderDisplayName: String? {
        switch gender {
        case "male": "Male"
        case "female": "Female"
        case "non_binary": "Non-binary"
        case "other": "Other"
        case "prefer_not_to_say": "Prefer not to say"
        default: nil
        }
    }

    var hasProfileDetails: Bool {
        dateOfBirth != nil || gender != nil || phone != nil || email != nil || address != nil
            || occupation != nil || profileNote != nil
    }
}

struct PatientProfileInput: Hashable, Codable, Sendable {
    let dateOfBirth: String?
    let gender: String?
    let phone: String?
    let email: String?
    let address: String?
    let occupation: String?
    let profileNote: String?

    private enum CodingKeys: String, CodingKey {
        case dateOfBirth, gender, phone, email, address, occupation, profileNote
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(gender, forKey: .gender)
        try container.encode(phone, forKey: .phone)
        try container.encode(email, forKey: .email)
        try container.encode(address, forKey: .address)
        try container.encode(occupation, forKey: .occupation)
        try container.encode(profileNote, forKey: .profileNote)
    }
}

struct ConsultationMessage: Identifiable, Hashable, Codable, Sendable {
    enum AuthorRole: String, Codable, Sendable { case agent, doctor, admin, system }

    let id: UUID
    let authorID: String?
    let author: String
    let role: AuthorRole
    let createdAt: Date
    let text: String
    let approximateGrafts: String?
    let recommendedPrice: String?
    let attachmentPhotoID: String?

    init(
        id: UUID = UUID(),
        authorID: String? = nil,
        author: String,
        role: AuthorRole,
        createdAt: Date = .now,
        text: String,
        approximateGrafts: String? = nil,
        recommendedPrice: String? = nil,
        attachmentPhotoID: String? = nil
    ) {
        self.id = id
        self.authorID = authorID
        self.author = author
        self.role = role
        self.createdAt = createdAt
        self.text = text
        self.approximateGrafts = approximateGrafts
        self.recommendedPrice = recommendedPrice
        self.attachmentPhotoID = attachmentPhotoID
    }
}

struct ConsultationCase: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let reference: String
    var patient: Patient
    let agentName: String
    var agencyName: String? = nil
    var assignedDoctorID: String?
    let uploadedAt: Date
    var status: ConsultationStatus
    var photoCount: Int
    var photoIDs: [String] = []
    var agentNote: String
    var agentGrafts: String
    var currency: String
    var agentPrice: String
    var finalGrafts: String? = nil
    var finalPrice: String? = nil
    var finalizedAt: Date? = nil
    var messages: [ConsultationMessage]
}

struct CasePhotoUpload: Identifiable, Sendable {
    let id: UUID
    let data: Data
    let contentType: String

    init(id: UUID = UUID(), data: Data, contentType: String) {
        self.id = id
        self.data = data
        self.contentType = contentType
    }
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
    let approximateGrafts: String?
    let recommendedPrice: String?
    let text: String
}
