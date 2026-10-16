import Foundation

protocol AdminRepository: Sendable {
    func fetchUsers() async throws -> [AdminUser]
    func fetchCases() async throws -> [AdminCase]
    func fetchAgencies() async throws -> [AdminAgency]
    func fetchIntakeForms() async throws -> [AdminIntakeForm]
    func createUser(username: String, displayName: String, role: UserRole, password: String, agencyID: String?) async throws -> AdminUser
    func updateUser(id: String, username: String, displayName: String, role: UserRole, password: String?, agencyID: String?) async throws -> AdminUser
    func setUserActive(id: String, active: Bool) async throws
    func deleteUser(id: String) async throws
    func createAgency(name: String, websiteURL: String?) async throws -> AdminAgency
    func updateAgency(id: String, name: String) async throws -> AdminAgency
    func updateIntakeForm(id: String, allowedOrigins: [String]) async throws -> AdminIntakeForm
    func setIntakeFormActive(id: String, active: Bool) async throws -> AdminIntakeForm
    func deleteAgency(id: String) async throws -> String
    func fetchMCPConnection(agencyID: String) async throws -> AdminMCPConnection
    func rotateMCPToken(agencyID: String) async throws -> AdminMCPConnection
    func exportAgencyIntegrationGuide(agencyID: String, accessToken: String?) async throws -> Data
    func transferPatientAgency(patientID: String, agencyID: String, reason: String) async throws
    func assignDoctor(patientID: String, doctorID: String?, reason: String) async throws
    func unconfirmCase(caseID: String) async throws
    func completeCase(caseID: String) async throws
    func deleteCase(caseID: String) async throws
    func purgePhoto(id: String) async throws
    func addOperationalNote(caseID: String, text: String) async throws
}
