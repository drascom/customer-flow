import Foundation

actor UserDefaultsAppTourStore: AppTourStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func hasCompleted(userID: String, serverAddress: String, role: UserRole, version: Int) -> Bool {
        defaults.bool(forKey: key(userID: userID, serverAddress: serverAddress, role: role, version: version))
    }

    func markCompleted(userID: String, serverAddress: String, role: UserRole, version: Int) {
        defaults.set(true, forKey: key(userID: userID, serverAddress: serverAddress, role: role, version: version))
    }

    private func key(userID: String, serverAddress: String, role: UserRole, version: Int) -> String {
        let identity = "\(serverAddress)|\(userID)|\(role.rawValue)|\(version)"
        let encoded = Data(identity.utf8).base64EncodedString()
        return "customerFlow.appTour.\(encoded)"
    }
}
