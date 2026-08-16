import SwiftUI

@main
struct CustomerFlowApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationAppDelegate.self) private var pushNotifications
    @StateObject private var state = AppState()
    @State private var tourModel: AppTourModel

    init() {
        let store = UserDefaultsAppTourStore(defaults: .standard)
        _tourModel = State(initialValue: AppTourModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(tourModel: tourModel)
                .environmentObject(state)
                .task { await state.bootstrap() }
                .task {
                    for await token in pushNotifications.deviceTokens() {
                        await state.receiveDeviceToken(token)
                    }
                }
                .task {
                    for await caseID in pushNotifications.openedCaseIDs() {
                        await state.openNotificationCase(caseID)
                    }
                }
                .task(id: state.phase == .authenticated ? state.currentUser?.id : nil) {
                    guard state.phase == .authenticated else { return }
                    _ = try? await pushNotifications.requestAuthorizationAndRegistration()
                }
        }
    }
}
