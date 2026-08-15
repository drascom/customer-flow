import Foundation

actor RemoteAdminRepository: AdminRepository {
    private let client: RemoteAPIClient

    init(client: RemoteAPIClient) {
        self.client = client
    }

    func fetchUsers() async throws -> [AdminUser] {
        struct Envelope: Decodable, Sendable { let users: [AdminUser] }
        let response: Envelope = try await client.get("admin/users")
        return response.users
    }

    func fetchCases() async throws -> [AdminCase] {
        struct Envelope: Decodable, Sendable { let cases: [AdminCase] }
        let response: Envelope = try await client.get("admin/cases")
        return response.cases
    }

    func fetchAgencies() async throws -> [AdminAgency] {
        struct Envelope: Decodable, Sendable { let agencies: [AdminAgency] }
        let response: Envelope = try await client.get("admin/agencies")
        return response.agencies
    }

    func createUser(
        username: String,
        displayName: String,
        role: UserRole,
        password: String,
        agencyID: String?
    ) async throws -> AdminUser {
        struct Body: Encodable, Sendable {
            let username: String
            let displayName: String
            let role: String
            let password: String
            let agencyID: String?
        }
        struct Envelope: Decodable, Sendable { let user: AdminUser }
        let response: Envelope = try await client.send("POST", path: "admin/users", body: Body(
            username: username,
            displayName: displayName,
            role: role.rawValue,
            password: password,
            agencyID: agencyID
        ))
        return response.user
    }

    func setUserActive(id: String, active: Bool) async throws {
        struct Body: Encodable, Sendable { let active: Bool }
        struct Mutation: Decodable, Sendable { let id: String; let active: Bool }
        struct Envelope: Decodable, Sendable { let user: Mutation }
        let _: Envelope = try await client.send("PATCH", path: "admin/users/\(id)", body: Body(active: active))
    }

    func updateUser(
        id: String,
        username: String,
        displayName: String,
        role: UserRole,
        password: String?,
        agencyID: String?
    ) async throws -> AdminUser {
        struct Body: Encodable, Sendable {
            let username: String
            let displayName: String
            let role: String
            let password: String?
            let agencyID: String?
        }
        struct Envelope: Decodable, Sendable { let user: AdminUser }
        let response: Envelope = try await client.send("PATCH", path: "admin/users/\(id)", body: Body(
            username: username,
            displayName: displayName,
            role: role.rawValue,
            password: password,
            agencyID: agencyID
        ))
        return response.user
    }

    func deleteUser(id: String) async throws {
        struct Empty: Encodable, Sendable {}
        struct Mutation: Decodable, Sendable { let id: String; let deleted: Bool }
        struct Envelope: Decodable, Sendable { let user: Mutation }
        let _: Envelope = try await client.send("DELETE", path: "admin/users/\(id)", body: Empty())
    }

    func createAgency(name: String) async throws -> AdminAgency {
        struct Body: Encodable, Sendable { let name: String }
        struct Envelope: Decodable, Sendable { let agency: AdminAgency }
        let response: Envelope = try await client.send("POST", path: "admin/agencies", body: Body(name: name))
        return response.agency
    }

    func updateAgency(id: String, name: String) async throws -> AdminAgency {
        struct Body: Encodable, Sendable { let name: String }
        struct Envelope: Decodable, Sendable { let agency: AdminAgency }
        let response: Envelope = try await client.send("PATCH", path: "admin/agencies/\(id)", body: Body(name: name))
        return response.agency
    }

    func assignDoctor(patientID: String, doctorID: String?, reason: String) async throws {
        struct Body: Encodable, Sendable { let doctorID: String?; let reason: String }
        struct Mutation: Decodable, Sendable { let patientID: String; let doctorID: String? }
        struct Envelope: Decodable, Sendable { let assignment: Mutation }
        let _: Envelope = try await client.send("PATCH", path: "admin/patients/\(patientID)", body: Body(
            doctorID: doctorID,
            reason: reason
        ))
    }
}
