import SwiftUI
import UIKit

enum AppTheme {
    static let brand = adaptive(
        light: UIColor(red: 47 / 255, green: 125 / 255, blue: 118 / 255, alpha: 1),
        dark: UIColor(red: 84 / 255, green: 184 / 255, blue: 173 / 255, alpha: 1)
    )
    static let brandDark = adaptive(
        light: UIColor(red: 38 / 255, green: 91 / 255, blue: 86 / 255, alpha: 1),
        dark: UIColor(red: 140 / 255, green: 221 / 255, blue: 210 / 255, alpha: 1)
    )
    static let accent = adaptive(
        light: UIColor(red: 201 / 255, green: 136 / 255, blue: 61 / 255, alpha: 1),
        dark: UIColor(red: 224 / 255, green: 164 / 255, blue: 93 / 255, alpha: 1)
    )
    static let accentInk = adaptive(
        light: UIColor(red: 58 / 255, green: 37 / 255, blue: 15 / 255, alpha: 1),
        dark: UIColor(red: 36 / 255, green: 21 / 255, blue: 9 / 255, alpha: 1)
    )
    static let canvas = adaptive(
        light: UIColor(red: 239 / 255, green: 232 / 255, blue: 222 / 255, alpha: 1),
        dark: UIColor(red: 43 / 255, green: 30 / 255, blue: 22 / 255, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(white: 1, alpha: 0.68),
        dark: UIColor(red: 25 / 255, green: 17 / 255, blue: 12 / 255, alpha: 0.78)
    )
    static let surfaceStrong = adaptive(
        light: UIColor(white: 1, alpha: 0.86),
        dark: UIColor(red: 20 / 255, green: 14 / 255, blue: 10 / 255, alpha: 0.9)
    )
    static let inset = adaptive(
        light: UIColor(red: 245 / 255, green: 239 / 255, blue: 231 / 255, alpha: 0.8),
        dark: UIColor(red: 31 / 255, green: 21 / 255, blue: 15 / 255, alpha: 0.84)
    )
    static let border = adaptive(
        light: UIColor(white: 1, alpha: 0.78),
        dark: UIColor(white: 1, alpha: 0.1)
    )
    static let ink = adaptive(
        light: UIColor(red: 28 / 255, green: 54 / 255, blue: 52 / 255, alpha: 1),
        dark: UIColor(red: 247 / 255, green: 240 / 255, blue: 231 / 255, alpha: 1)
    )
    static let muted = adaptive(
        light: UIColor(red: 96 / 255, green: 117 / 255, blue: 113 / 255, alpha: 1),
        dark: UIColor(red: 198 / 255, green: 188 / 255, blue: 177 / 255, alpha: 1)
    )

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                adaptive(
                    light: UIColor(red: 215 / 255, green: 226 / 255, blue: 239 / 255, alpha: 1),
                    dark: UIColor(red: 101 / 255, green: 117 / 255, blue: 139 / 255, alpha: 1)
                ),
                adaptive(
                    light: UIColor(red: 240 / 255, green: 230 / 255, blue: 216 / 255, alpha: 1),
                    dark: UIColor(red: 84 / 255, green: 73 / 255, blue: 64 / 255, alpha: 1)
                ),
                adaptive(
                    light: UIColor(red: 239 / 255, green: 211 / 255, blue: 170 / 255, alpha: 1),
                    dark: UIColor(red: 72 / 255, green: 43 / 255, blue: 23 / 255, alpha: 1)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct ClinicalPhotoPlaceholder: View {
    let index: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: index.isMultiple(of: 2)
                    ? [Color(red: 0.82, green: 0.65, blue: 0.56), Color(red: 0.43, green: 0.31, blue: 0.27)]
                    : [Color(red: 0.72, green: 0.54, blue: 0.47), Color(red: 0.28, green: 0.21, blue: 0.19)],
                startPoint: .top,
                endPoint: .bottom
            )
            Ellipse()
                .fill(Color.black.opacity(0.42))
                .frame(width: 120, height: 58)
                .offset(y: -28)
            Text("DEMO CLINICAL IMAGE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(8)
                .background(.black.opacity(0.24), in: Capsule())
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(12)
        }
        .accessibilityLabel("Demo patient photo \(index + 1)")
    }
}

struct ClinicalPhotoView: View {
    @EnvironmentObject private var state: AppState
    let photoID: String?
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .accessibilityLabel("Patient photo \(index + 1)")
            } else {
                ClinicalPhotoPlaceholder(index: index)
                    .overlay {
                        if photoID != nil { ProgressView().tint(.white) }
                    }
            }
        }
        .task(id: photoID) {
            image = nil
            guard let photoID, let data = await state.loadPhoto(id: photoID) else { return }
            image = UIImage(data: data)
        }
    }
}
