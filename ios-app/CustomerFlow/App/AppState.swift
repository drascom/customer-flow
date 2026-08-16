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
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadNotificationCount = 0
    @Published var pendingNotificationCaseID: UUID?
    @Published private(set) var liveRevision = 0
    @Published private(set) var isRefreshingAfterForeground = false
    @Published var errorMessage: String?
    @Published var isWorking = false

    var role: UserRole { currentUser?.role ?? .doctor }
    var currentDoctorID: String { role == .doctor ? currentUser?.id ?? "" : "" }
    var currentDoctorName: String { role == .doctor ? currentUser?.displayName ?? "Doctor" : "Doctor" }
    var currentAgentName: String { role == .agent ? currentUser?.displayName ?? "Agent" : "Agent" }
    var savedServerAddress: String {
        UserDefaults.standard.string(forKey: serverAddressKey) ?? "https://flow.drascom.uk"
    }

    private(set) var patientMatcher: any PatientMatchingService = MockPatientMatchingService()
    private(set) var adminRepository: (any AdminRepository)?
    private var repository: any CaseRepository = MockCaseRepository()
    private let notificationService: any NotificationService
    private var remoteClient: RemoteAPIClient?
    private var liveUpdatesTask: Task<Void, Never>?
    private var caseLoadInProgress = false
    private var caseReloadRequested = false
    private var deviceTokenHex: String?
    private let photoCache = NSCache<NSString, NSData>()
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
                await registerPendingNotificationDevice()
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
            await registerPendingNotificationDevice()
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() async {
        isWorking = true
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        await unregisterNotificationDevice()
        await remoteClient?.logout()
        SecureTokenStore.clear()
        currentUser = nil
        cases = []
        notifications = []
        unreadNotificationCount = 0
        pendingNotificationCaseID = nil
        photoCache.removeAllObjects()
        adminRepository = nil
        repository = MockCaseRepository()
        patientMatcher = MockPatientMatchingService()
        phase = .login
        isWorking = false
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
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        await unregisterNotificationDevice()
        await remoteClient?.logout()
        SecureTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: serverAddressKey)
        remoteClient = nil
        currentUser = nil
        cases = []
        notifications = []
        unreadNotificationCount = 0
        pendingNotificationCaseID = nil
        photoCache.removeAllObjects()
        adminRepository = nil
        connectedServerName = "Customer Flow Server"
        phase = .serverSetup
    }

    func load() async {
        guard phase == .authenticated else { return }
        guard !caseLoadInProgress else {
            caseReloadRequested = true
            return
        }

        caseLoadInProgress = true
        defer { caseLoadInProgress = false }
        repeat {
            caseReloadRequested = false
            do {
                let updatedCases = try await repository.fetchCases()
                guard phase == .authenticated else { return }
                cases = updatedCases
                await loadNotifications()
            } catch {
                guard !Self.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        } while caseReloadRequested && phase == .authenticated
    }

    func refreshAfterForeground() async {
        guard phase == .authenticated, let remoteClient else { return }
        isRefreshingAfterForeground = true
        defer { isRefreshingAfterForeground = false }
        startLiveUpdates(client: remoteClient)
        await load()
        guard phase == .authenticated else { return }
        liveRevision &+= 1
    }

    func createCase(patientName: String, patientProfile: PatientProfileInput, grafts: String, currency: String, price: String, note: String,
                    photos: [CasePhotoUpload], duplicateConfirmedDifferent: Bool) async -> Bool {
        do {
            var created = try await repository.createCase(
                patientName: patientName,
                patientProfile: patientProfile,
                agentName: currentAgentName,
                grafts: grafts,
                currency: currency,
                price: price,
                note: note,
                photoCount: photos.count,
                duplicateConfirmedDifferent: duplicateConfirmedDifferent
            )
            for photo in photos {
                created = try await repository.uploadPhoto(
                    caseID: created.id, data: photo.data, contentType: photo.contentType
                )
            }
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadPhotos(caseID: UUID, photos: [CasePhotoUpload]) async -> Bool {
        do {
            var updated: ConsultationCase?
            for photo in photos {
                updated = try await repository.uploadPhoto(
                    caseID: caseID, data: photo.data, contentType: photo.contentType
                )
            }
            if let updated { replace(updated) }
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load()
            return false
        }
    }

    func deletePhoto(caseID: UUID, photoID: String) async -> Bool {
        do {
            let updated = try await repository.deletePhoto(caseID: caseID, photoID: photoID)
            photoCache.removeObject(forKey: photoID as NSString)
            replace(updated)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load()
            return false
        }
    }

    func photoData(photoID: String) async throws -> Data {
        if let cached = photoCache.object(forKey: photoID as NSString) {
            return cached as Data
        }
        let data = try await repository.fetchPhoto(photoID: photoID)
        photoCache.setObject(data as NSData, forKey: photoID as NSString)
        return data
    }

    func sendPhotoMessage(
        caseID: UUID, data: Data, contentType: String, text: String = ""
    ) async -> Bool {
        do {
            let previousIDs = Set(
                cases.first(where: { $0.id == caseID })?.messages.compactMap(\.attachmentPhotoID) ?? []
            )
            let updated = try await repository.sendPhotoMessage(
                caseID: caseID, data: data, contentType: contentType, text: text
            )
            if let attachmentID = updated.messages.compactMap(\.attachmentPhotoID).last(where: { !previousIDs.contains($0) }) {
                photoCache.setObject(data as NSData, forKey: attachmentID as NSString)
            }
            replace(updated)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load()
            return false
        }
    }

    func messagePhotoData(messageID: String) async throws -> Data {
        if let cached = photoCache.object(forKey: messageID as NSString) {
            return cached as Data
        }
        let data = try await repository.fetchMessagePhoto(messageID: messageID)
        photoCache.setObject(data as NSData, forKey: messageID as NSString)
        return data
    }

    func deleteMessage(caseID: UUID, messageID: UUID) async -> Bool {
        do {
            let updated = try await repository.deleteMessage(caseID: caseID, messageID: messageID)
            photoCache.removeObject(forKey: messageID.uuidString as NSString)
            replace(updated)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load()
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

    func saveAgentValues(caseID: UUID, patientName: String, patientProfile: PatientProfileInput, grafts: String, currency: String, price: String) async -> Bool {
        do {
            try await repository.saveAgentValues(
                caseID: caseID, patientName: patientName, patientProfile: patientProfile,
                grafts: grafts, currency: currency, price: price
            )
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmAndClose(caseID: UUID, finalGrafts: String, finalPrice: String) async -> Bool {
        do {
            try await repository.confirmAndClose(
                caseID: caseID,
                finalGrafts: finalGrafts,
                finalPrice: finalPrice
            )
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

    func receiveDeviceToken(_ token: Data) async {
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
        await registerPendingNotificationDevice()
    }

    func loadNotifications() async {
        guard phase == .authenticated, let remoteClient else { return }
        do {
            let inbox = try await remoteClient.fetchNotifications()
            notifications = inbox.notifications
            unreadNotificationCount = inbox.unreadCount
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func markAllNotificationsRead() async {
        guard let remoteClient, unreadNotificationCount > 0 else { return }
        do {
            try await remoteClient.markAllNotificationsRead()
            let now = Date()
            notifications = notifications.map { item in
                var updated = item
                if updated.readAt == nil { updated.readAt = now }
                return updated
            }
            unreadNotificationCount = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openNotification(_ notification: AppNotification) async {
        if notification.readAt == nil, let remoteClient {
            do {
                try await remoteClient.markNotificationsRead([notification.id])
                if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                    notifications[index].readAt = Date()
                }
                unreadNotificationCount = max(0, unreadNotificationCount - 1)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await load()
        pendingNotificationCaseID = notification.caseID
    }

    func openNotificationCase(_ caseID: UUID) async {
        await load()
        pendingNotificationCaseID = caseID
    }

    func consumePendingNotificationCase() {
        pendingNotificationCaseID = nil
    }

    private func activate(client: RemoteAPIClient, user: AuthenticatedUser) {
        repository = RemoteCaseRepository(client: client)
        patientMatcher = RemotePatientMatchingService(client: client)
        adminRepository = user.role == .admin || user.role == .manager
            ? RemoteAdminRepository(client: client)
            : nil
        currentUser = user
        startLiveUpdates(client: client)
    }

    private func registerPendingNotificationDevice() async {
        guard phase == .authenticated, let remoteClient, let deviceTokenHex else { return }
        do {
            try await remoteClient.registerNotificationDevice(
                token: deviceTokenHex, environment: Self.notificationEnvironment
            )
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func unregisterNotificationDevice() async {
        guard let remoteClient, let deviceTokenHex else { return }
        try? await remoteClient.unregisterNotificationDevice(token: deviceTokenHex)
    }

    private static var notificationEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func startLiveUpdates(client: RemoteAPIClient) {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }
            var revision = 0

            while !Task.isCancelled {
                do {
                    let update = try await client.waitForChanges(since: revision)
                    guard !Task.isCancelled else { return }
                    revision = update.revision
                    guard update.changed else { continue }
                    await load()
                    liveRevision &+= 1
                } catch {
                    if Task.isCancelled || Self.isCancellation(error) { return }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let cocoaError = error as NSError
        return cocoaError.domain == NSURLErrorDomain && cocoaError.code == NSURLErrorCancelled
    }

    private func replace(_ updated: ConsultationCase) {
        guard let index = cases.firstIndex(where: { $0.id == updated.id }) else { return }
        cases[index] = updated
    }
}
