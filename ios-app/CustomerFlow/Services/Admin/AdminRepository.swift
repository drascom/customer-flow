import Foundation

protocol AdminRepository: Sendable {
    func fetchUsers() async throws -> [AdminUser]
    func fetchCases() async throws -> [AdminCase]
    func fetchAgencies() async throws -> [AdminAgency]
    func createUser(username: String, displayName: String, role: UserRole, password: String, agencyID: String?) async throws -> AdminUser
    func setUserActive(id: String, active: Bool) async throws
    func deleteUser(id: String) async throws
    func createAgency(name: String) async throws -> AdminAgency
    func assignDoctor(patientID: String, doctorID: String?, reason: String) async throws
}
