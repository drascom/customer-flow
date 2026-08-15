import Foundation

struct AdminCasePhoto: Identifiable, Decodable, Sendable {
    let id: String
    let position: Int
    let available: Bool
    let deleted: Bool
    let deletedAt: Date?
    let deletedByName: String?
}

struct AdminCaseMessage: Identifiable, Decodable, Sendable {
    let id: String
    let author: String
    let role: ConsultationMessage.AuthorRole
    let createdAt: Date
    let text: String
    let approximateGrafts: String?
    let recommendedPrice: String?
    let attachmentPhotoID: String?
    let deletedAt: Date?
    let deletedByName: String?
}

struct AdminCase: Identifiable, Decodable, Sendable {
    let id: String
    let reference: String
    let patientID: String
    let patientName: String
    let agentName: String
    var agencyName: String?
    var doctorID: String?
    var doctorName: String?
    let uploadedAt: Date
    let status: ConsultationStatus
    let photoCount: Int
    let deletedPhotoCount: Int
    let photos: [AdminCasePhoto]
    let messages: [AdminCaseMessage]
    let messageCount: Int
    let deletedMessageCount: Int
    let latestMessageAuthor: String?
    let latestMessageText: String?
    let latestMessageAt: Date?
    let latestMessageHasPhoto: Bool?
    let grafts: String
    let currency: String
    let price: String
    let finalGrafts: String?
    let finalPrice: String?
    let finalizedAt: Date?
}
