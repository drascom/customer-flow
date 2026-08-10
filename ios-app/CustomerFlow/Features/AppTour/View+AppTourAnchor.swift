import SwiftUI

extension View {
    @ViewBuilder
    func appTourAnchor(_ target: AppTourTarget?) -> some View {
        if let target {
            anchorPreference(key: AppTourAnchorPreferenceKey.self, value: .bounds) {
                [target: $0]
            }
        } else {
            self
        }
    }
}
