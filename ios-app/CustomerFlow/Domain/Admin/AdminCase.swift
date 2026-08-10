import Foundation

struct AdminCase: Identifiable, Decodable, Sendable {
    let id: String
    let reference: String
    let patientID: String
    let patientName: String
    let agentName: String
    let agencyName: String?
    var doctorID: String?
    var doctorName: String?
    let uploadedAt: Date
    let status: ConsultationStatus
    let photoCount: Int
    let messageCount: Int
    let grafts: String
    let currency: String
    let price: String
}
