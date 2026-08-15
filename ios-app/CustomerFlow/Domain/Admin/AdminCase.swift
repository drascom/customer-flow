import Foundation

struct AdminCasePhoto: Identifiable, Decodable, Sendable {
    let id: String
    let position: Int
    let available: Bool
    let deleted: Bool
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
    let messageCount: Int
    let latestMessageAuthor: String?
    let latestMessageText: String?
    let latestMessageAt: Date?
    let latestMessageHasPhoto: Bool?
    let grafts: String
    let currency: String
    let price: String
}
