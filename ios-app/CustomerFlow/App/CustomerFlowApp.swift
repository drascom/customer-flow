import SwiftUI

@main
struct CustomerFlowApp: App {
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
        }
    }
}
