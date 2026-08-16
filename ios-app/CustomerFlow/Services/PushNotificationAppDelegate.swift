import UIKit
import UserNotifications

@MainActor
final class PushNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var latestToken: Data?
    private var tokenContinuations: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var caseContinuations: [UUID: AsyncStream<UUID>.Continuation] = [:]

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func requestAuthorizationAndRegistration() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        )
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    func deviceTokens() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let id = UUID()
            tokenContinuations[id] = continuation
            if let latestToken { continuation.yield(latestToken) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.tokenContinuations.removeValue(forKey: id) }
            }
        }
    }

    func openedCaseIDs() -> AsyncStream<UUID> {
        AsyncStream { continuation in
            let id = UUID()
            caseContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.caseContinuations.removeValue(forKey: id) }
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        latestToken = token
        tokenContinuations.values.forEach { $0.yield(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulator and unsigned development builds can legitimately reach this boundary.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let rawCaseID = response.notification.request.content.userInfo["caseID"] as? String,
              let caseID = UUID(uuidString: rawCaseID) else { return }
        caseContinuations.values.forEach { $0.yield(caseID) }
    }
}
