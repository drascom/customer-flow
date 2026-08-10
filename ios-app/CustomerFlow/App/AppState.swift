import Foundation

enum AppPhase: Equatable {
    case restoring
    case serverSetup
    case login
    case authenticated
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var phase: AppPhase = .restoring
    @Published private(set) var currentUser: AuthenticatedUser?
    @Published private(set) var connectedServerName = "Customer Flow Server"
    @Published private(set) var cases: [ConsultationCase] = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    var role: UserRole { currentUser?.role ?? .doctor }
    var currentDoctorID: String { role == .doctor ? currentUser?.id ?? "" : "" }
    var currentDoctorName: String { role == .doctor ? currentUser?.displayName ?? "Doctor" : "Doctor" }
    var currentAgentName: String { role == .agent ? currentUser?.displayName ?? "Agent" : "Agent" }
    var savedServerAddress: String { UserDefaults.standard.string(forKey: serverAddressKey) ?? "" }

    private(set) var patientMatcher: any PatientMatchingService = MockPatientMatchingService()
    private(set) var adminRepository: (any AdminRepository)?
    private var repository: any CaseRepository = MockCaseRepository()
    private let notificationService: any NotificationService
    private var remoteClient: RemoteAPIClient?
    private let serverAddressKey = "customerFlow.serverAddress"

    init(notificationService: any NotificationService = NoopNotificationService()) {
        self.notificationService = notificationService
    }

    func bootstrap() async {
        guard !savedServerAddress.isEmpty else {
            phase = .serverSetup
            return
        }
        do {
            let baseURL = try ServerAddress.normalize(savedServerAddress)
            let token = SecureTokenStore.load()
            let client = RemoteAPIClient(baseURL: baseURL, accessToken: token)
            let health = try await client.health()
            remoteClient = client
            connectedServerName = health.service
            guard token != nil else {
                phase = .login
                return
            }
            do {
                let user = try await client.restoreSession()
                activate(client: client, user: user)
                phase = .authenticated
                await load()
            } catch {
                SecureTokenStore.clear()
                await client.setAccessToken(nil)
                phase = .login
            }
        } catch {
            SecureTokenStore.clear()
            remoteClient = nil
            phase = .serverSetup
            errorMessage = error.localizedDescription
        }
    }

    func connect(serverAddress: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let baseURL = try ServerAddress.normalize(serverAddress)
            let client = RemoteAPIClient(baseURL: baseURL)
            let health = try await client.health()
            UserDefaults.standard.set(baseURL.absoluteString, forKey: serverAddressKey)
            remoteClient = client
            connectedServerName = health.service
            phase = .login
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func login(username: String, password: String) async -> Bool {
        guard let remoteClient else {
            phase = .serverSetup
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await remoteClient.login(username: username, password: password)
            try SecureTokenStore.save(session.token)
            activate(client: remoteClient, user: session.user)
            phase = .authenticated
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() async {
        isWorking = true
        await remoteClient?.logout()
        SecureTokenStore.clear()
        currentUser = nil
        cases = []
        adminRepository = nil
        repository = MockCaseRepository()
        patientMatcher = MockPatientMatchingService()
        phase = .login
        isWorking = false
    }

    func loadPhoto(id: String) async -> Data? {
        guard let remoteClient else { return nil }
        return try? await remoteClient.photo(id: id)
    }

    func updateProfile(displayName: String, email: String, phone: String) async -> Bool {
        guard let remoteClient else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            currentUser = try await remoteClient.updateProfile(displayName: displayName, email: email, phone: phone)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard let remoteClient else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await remoteClient.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestPasswordReset(identifier: String) async -> String? {
        guard let remoteClient else {
            phase = .serverSetup
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            return try await remoteClient.requestPasswordReset(identifier: identifier)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func resetPassword(identifier: String, code: String, newPassword: String) async -> Bool {
        guard let remoteClient else {
            phase = .serverSetup
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await remoteClient.resetPassword(identifier: identifier, code: code, newPassword: newPassword)
            SecureTokenStore.clear()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func changeServer() async {
        await remoteClient?.logout()
        SecureTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: serverAddressKey)
        remoteClient = nil
        currentUser = nil
        cases = []
        adminRepository = nil
        connectedServerName = "Customer Flow Server"
        phase = .serverSetup
    }

    func load() async {
        guard phase == .authenticated else { return }
        do { cases = try await repository.fetchCases() }
        catch { errorMessage = error.localizedDescription }
    }

    func createCase(patientName: String, grafts: String, currency: String, price: String, note: String,
                    photoCount: Int, duplicateConfirmedDifferent: Bool) async -> Bool {
        do {
            _ = try await repository.createCase(
                patientName: patientName,
                agentName: currentAgentName,
                grafts: grafts,
                currency: currency,
                price: price,
                note: note,
                photoCount: photoCount,
                duplicateConfirmedDifferent: duplicateConfirmedDifferent
            )
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendRecommendation(caseID: UUID, recommendation: DoctorRecommendation) async -> Bool {
        do {
            let updated = try await repository.sendRecommendation(caseID: caseID, doctorID: currentDoctorID, recommendation: recommendation)
            replace(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load()
            return false
        }
    }

    func saveAgentValues(caseID: UUID, patientName: String, grafts: String, currency: String, price: String) async -> Bool {
        do {
            try await repository.saveAgentValues(caseID: caseID, patientName: patientName, grafts: grafts, currency: currency, price: price)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmAndClose(caseID: UUID) async -> Bool {
        do {
            try await repository.confirmAndClose(caseID: caseID)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendAgentUpdate(caseID: UUID, text: String) async -> Bool {
        do {
            try await repository.sendAgentUpdate(caseID: caseID, text: text)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestNotifications() async {
        do { _ = try await notificationService.requestAuthorization() }
        catch { errorMessage = error.localizedDescription }
    }

    private func activate(client: RemoteAPIClient, user: AuthenticatedUser) {
        repository = RemoteCaseRepository(client: client)
        patientMatcher = RemotePatientMatchingService(client: client)
        adminRepository = user.role == .admin || user.role == .manager ? RemoteAdminRepository(client: client) : nil
        currentUser = user
    }

    private func replace(_ updated: ConsultationCase) {
        guard let index = cases.firstIndex(where: { $0.id == updated.id }) else { return }
        cases[index] = updated
    }
}
