import SwiftUI

struct AppTourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [AppTourTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AppTourTarget: Anchor<CGRect>],
        nextValue: () -> [AppTourTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
