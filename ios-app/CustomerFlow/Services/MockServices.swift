import Foundation

@MainActor
final class MockCaseRepository: CaseRepository {
    private var cases: [ConsultationCase] = MockData.cases

    func fetchCases() async throws -> [ConsultationCase] { cases }

    func createCase(patientName: String, patientProfile: PatientProfileInput, agentName: String, grafts: String, currency: String, price: String, note: String, photoCount: Int, duplicateConfirmedDifferent: Bool) async throws -> ConsultationCase {
        let sequence = 240900 + cases.count + 1
        let patientSequence = 1100 + cases.count + 1
        let item = ConsultationCase(
            id: UUID(),
            reference: "HT-\(sequence)",
            patient: Patient(
                id: "PT-\(patientSequence)", name: patientName,
                dateOfBirth: patientProfile.dateOfBirth, gender: patientProfile.gender,
                phone: patientProfile.phone, email: patientProfile.email, address: patientProfile.address,
                occupation: patientProfile.occupation, profileNote: patientProfile.profileNote,
                assignedDoctorID: nil, lastUpdated: .now
            ),
            agentName: agentName,
            assignedDoctorID: nil,
            uploadedAt: .now,
            status: .waiting,
            photoCount: photoCount,
            agentNote: note,
            agentGrafts: grafts,
            currency: currency,
            agentPrice: price,
            messages: [.init(author: agentName, role: .agent, text: "Patient photos and consultation information uploaded.")]
        )
        cases.insert(item, at: 0)
        return item
    }

    func uploadPhoto(caseID: UUID, data: Data, contentType: String) async throws -> ConsultationCase {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].photoIDs.append(UUID().uuidString)
        if cases[index].photoIDs.count > cases[index].photoCount {
            cases[index].photoCount = cases[index].photoIDs.count
        }
        cases[index].status = .waiting
        return cases[index]
    }

    func deletePhoto(caseID: UUID, photoID: String) async throws -> ConsultationCase {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        guard let photoIndex = cases[index].photoIDs.firstIndex(of: photoID) else { throw MockError.notFound }
        cases[index].photoIDs.remove(at: photoIndex)
        cases[index].photoCount = cases[index].photoIDs.count
        cases[index].status = .waiting
        return cases[index]
    }

    func fetchPhoto(photoID: String) async throws -> Data {
        throw MockError.notFound
    }

    func sendPhotoMessage(caseID: UUID, data: Data, contentType: String) async throws -> ConsultationCase {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].messages.append(.init(
            author: "Current User",
            role: .agent,
            text: "Annotated patient photo",
            attachmentPhotoID: UUID().uuidString
        ))
        return cases[index]
    }

    func fetchMessagePhoto(messageID: String) async throws -> Data {
        throw MockError.notFound
    }

    func deleteMessage(caseID: UUID, messageID: UUID) async throws -> ConsultationCase {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].messages.removeAll { $0.id == messageID }
        return cases[index]
    }

    func sendRecommendation(caseID: UUID, doctorID: String, recommendation: DoctorRecommendation) async throws -> ConsultationCase {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        guard cases[index].status != .closed else { throw MockError.caseChanged }

        if let assigned = cases[index].assignedDoctorID, assigned != doctorID {
            throw MockError.caseChanged
        }

        cases[index].assignedDoctorID = doctorID
        cases[index].patient.assignedDoctorID = doctorID
        cases[index].status = .answered
        cases[index].messages.append(
            ConsultationMessage(
                author: "Dr. Emre Kaya",
                role: .doctor,
                text: recommendation.text,
                approximateGrafts: recommendation.approximateGrafts,
                recommendedPrice: recommendation.recommendedPrice
            )
        )
        return cases[index]
    }

    func saveAgentValues(caseID: UUID, patientName: String, patientProfile: PatientProfileInput, grafts: String, currency: String, price: String) async throws {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].patient.name = patientName
        cases[index].patient.dateOfBirth = patientProfile.dateOfBirth
        cases[index].patient.gender = patientProfile.gender
        cases[index].patient.phone = patientProfile.phone
        cases[index].patient.email = patientProfile.email
        cases[index].patient.address = patientProfile.address
        cases[index].patient.occupation = patientProfile.occupation
        cases[index].patient.profileNote = patientProfile.profileNote
        cases[index].patient.lastUpdated = .now
        cases[index].agentGrafts = grafts
        cases[index].currency = currency
        cases[index].agentPrice = price
    }

    func confirmAndClose(caseID: UUID, finalGrafts: String, finalPrice: String) async throws {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].finalGrafts = finalGrafts
        cases[index].finalPrice = finalPrice
        cases[index].finalizedAt = .now
        cases[index].status = .closed
    }

    func sendAgentUpdate(caseID: UUID, text: String) async throws {
        guard let index = cases.firstIndex(where: { $0.id == caseID }) else { throw MockError.notFound }
        cases[index].messages.append(.init(author: "Selin Arslan", role: .agent, text: text))
        cases[index].status = .waiting
    }

    enum MockError: LocalizedError {
        case notFound
        case caseChanged

        var errorDescription: String? {
            switch self {
            case .notFound: "The case could not be found."
            case .caseChanged: "This case was already answered or assigned. Refresh to see its current state."
            }
        }
    }
}

struct MockPatientMatchingService: PatientMatchingService {
    func findMatches(for patientName: String) async throws -> [PatientMatchCandidate] {
        let queryTokens = nameTokens(patientName)
        guard queryTokens.count >= 2 else { return [] }

        return MockData.cases
            .filter { queryTokens.isSubset(of: nameTokens($0.patient.name)) }
            .reduce(into: [PatientMatchCandidate]()) { result, item in
                guard !result.contains(where: { $0.id == item.patient.id }) else { return }
                result.append(
                    PatientMatchCandidate(
                        id: item.patient.id,
                        name: item.patient.name,
                        assignedDoctorName: item.assignedDoctorID == nil ? nil : "Dr. Emre Kaya",
                        lastUpdated: item.patient.lastUpdated,
                        createdByAnotherAgent: item.agentName != "Selin Arslan",
                        photoCount: item.photoCount
                    )
                )
            }
    }

    private func nameTokens(_ value: String) -> Set<String> {
        let locale = Locale(identifier: "tr_TR")
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .lowercased(with: locale)
        return Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}

enum MockData {
    static let doctorID = "doctor-emre"

    static let cases: [ConsultationCase] = [
        makeCase(reference: "HT-240814", patientID: "PT-1042", patient: "Daniel Morris", agent: "Selin Arslan", assignedDoctorID: doctorID, hoursAgo: 8, photos: 4, grafts: "3,200", price: "2,850", note: "Diffuse thinning across the frontal and mid-scalp area. Please assess the graft range and whether the crown should be planned for the same session."),
        makeCase(reference: "HT-240825", patientID: "PT-1071", patient: "Ayhan Çolak", agent: "Mert Demir", assignedDoctorID: doctorID, hoursAgo: 12, photos: 3, grafts: "2,700", price: "2,550", note: "Frontal hairline restoration request with progressive temporal recession. Please review the donor area and proposed graft range."),
        makeCase(reference: "HT-240817", patientID: "PT-1051", patient: "Liam Wilson", agent: "Mert Demir", assignedDoctorID: doctorID, hoursAgo: 5, photos: 3, grafts: "2,400", price: "2,350", note: "Patient requests a conservative frontal hairline. No previous surgery. Please advise whether medical stabilisation is recommended first."),
        makeCase(reference: "HT-240821", patientID: "PT-1060", patient: "Ethan Cole", agent: "Aylin Yılmaz", assignedDoctorID: nil, hoursAgo: 2, photos: 4, grafts: "1,800", price: "2,100", note: "Second opinion requested after a previous FUE procedure. Please review corrective options."),
        makeCase(reference: "HT-240803", patientID: "PT-1037", patient: "Noah Bennett", agent: "Selin Arslan", assignedDoctorID: doctorID, hoursAgo: 28, status: .answered, photos: 3, grafts: "2,600", price: "2,500", note: "Receding hairline with good donor density. Recommendation is waiting for agent confirmation.", includeDoctorReply: true),
        makeCase(reference: "HT-240799", patientID: "PT-1029", patient: "Oliver Grant", agent: "Cem Öztürk", assignedDoctorID: doctorID, hoursAgo: 48, status: .answered, photos: 4, grafts: "3,000", price: "2,800", note: "Crown-focused case. Recommendation has been sent.", includeDoctorReply: true),
        makeCase(reference: "HT-240764", patientID: "PT-0998", patient: "George Hall", agent: "Aylin Yılmaz", assignedDoctorID: doctorID, hoursAgo: 96, status: .closed, photos: 3, grafts: "2,200", price: "2,300", note: "Frontal restoration consultation completed and confirmed.", includeDoctorReply: true)
    ]

    private static func makeCase(
        reference: String,
        patientID: String,
        patient: String,
        agent: String,
        assignedDoctorID: String?,
        hoursAgo: Int,
        status: ConsultationStatus = .waiting,
        photos: Int,
        grafts: String,
        price: String,
        note: String,
        includeDoctorReply: Bool = false
    ) -> ConsultationCase {
        let date = Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: .now) ?? .now
        var messages = [ConsultationMessage(author: agent, role: .agent, createdAt: date, text: "Patient photos and consultation information uploaded.")]
        if includeDoctorReply {
            messages.append(.init(author: "Dr. Emre Kaya", role: .doctor, createdAt: date.addingTimeInterval(3600), text: "The donor area appears suitable, subject to an in-person density measurement.", approximateGrafts: "2,400–2,700", recommendedPrice: "£2,600"))
        }
        return ConsultationCase(
            id: UUID(),
            reference: reference,
            patient: Patient(id: patientID, name: patient, assignedDoctorID: assignedDoctorID, lastUpdated: date),
            agentName: agent,
            assignedDoctorID: assignedDoctorID,
            uploadedAt: date,
            status: status,
            photoCount: photos,
            agentNote: note,
            agentGrafts: grafts,
            currency: AppCurrency.code,
            agentPrice: price,
            messages: messages
        )
    }
}
