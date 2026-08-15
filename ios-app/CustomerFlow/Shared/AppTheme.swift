import SwiftUI
import UIKit
import QuickLook

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

struct CasePhotoView: View {
    @EnvironmentObject private var state: AppState

    let photoID: String?
    let index: Int
    var reloadToken: Int = 0
    var onDelete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Patient photo \(index + 1)")
            } else {
                ClinicalPhotoPlaceholder(index: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            guard image != nil else { return }
            onTap?()
        }
        .overlay(alignment: .topTrailing) {
            if image != nil, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.red.opacity(0.88), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Remove photo \(index + 1)")
            }
        }
        .task(id: "\(photoID ?? "missing"):\(reloadToken)") {
            image = nil
            guard let photoID else { return }
            guard let data = try? await state.photoData(photoID: photoID),
                  let loaded = UIImage(data: data) else { return }
            image = loaded
        }
    }
}

struct NativePhotoPreviewRequest: Identifiable {
    let id = UUID()
    let caseID: UUID
    let fileURLs: [URL]
    let initialIndex: Int
    let allowsEditing: Bool

    static func make(
        caseID: UUID,
        photoIDs: [String],
        photoData: [String: Data],
        initialIndex: Int,
        allowsEditing: Bool
    ) throws -> NativePhotoPreviewRequest {
        guard !photoIDs.isEmpty else { throw PreviewError.noPhotos }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomerFlowQuickLook", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURLs = try photoIDs.map { photoID in
            guard let data = photoData[photoID] else { throw PreviewError.missingPhoto }
            let fileURL = directory.appendingPathComponent(
                "\(photoID)-\(UUID().uuidString).\(fileExtension(for: data))"
            )
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
        let safeIndex = fileURLs.indices.contains(initialIndex) ? initialIndex : 0
        return NativePhotoPreviewRequest(
            caseID: caseID,
            fileURLs: fileURLs,
            initialIndex: safeIndex,
            allowsEditing: allowsEditing
        )
    }

    private static func fileExtension(for data: Data) -> String {
        let fileExtension: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            fileExtension = "png"
        } else if data.count > 12, String(data: data[8..<12], encoding: .ascii) == "ftyp" {
            fileExtension = "heic"
        } else {
            fileExtension = "jpg"
        }
        return fileExtension
    }

    enum PreviewError: Error { case noPhotos, missingPhoto }
}

private final class NumberedPhotoPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, position: Int) {
        previewItemURL = url
        previewItemTitle = "\(position + 1)"
    }
}

struct NativePhotoPreview: UIViewControllerRepresentable {
    let request: NativePhotoPreviewRequest
    let onEdited: (Data, String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(request: request, onEdited: onEdited, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.currentPreviewItemIndex = request.initialIndex
        context.coordinator.previewController = controller
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.closePreview)
        )
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        return navigationController
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let request: NativePhotoPreviewRequest
        let onEdited: (Data, String) -> Void
        let onClose: () -> Void
        private var sentEditedFiles: Set<URL> = []
        weak var previewController: QLPreviewController?

        init(
            request: NativePhotoPreviewRequest,
            onEdited: @escaping (Data, String) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.request = request
            self.onEdited = onEdited
            self.onClose = onClose
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { request.fileURLs.count }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            NumberedPhotoPreviewItem(url: request.fileURLs[index], position: index)
        }

        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            request.allowsEditing ? .updateContents : .disabled
        }

        func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
            guard let fileURL = previewItem.previewItemURL else { return }
            sendEditedFile(at: fileURL)
        }

        func previewController(
            _ controller: QLPreviewController,
            didSaveEditedCopyOf previewItem: QLPreviewItem,
            at modifiedContentsURL: URL
        ) {
            sendEditedFile(at: modifiedContentsURL)
        }

        @objc func closePreview() {
            onClose()
        }

        private func sendEditedFile(at fileURL: URL) {
            let normalizedURL = fileURL.standardizedFileURL
            guard !sentEditedFiles.contains(normalizedURL), let data = try? Data(contentsOf: fileURL) else { return }
            sentEditedFiles.insert(normalizedURL)
            let contentType: String
            switch fileURL.pathExtension.lowercased() {
            case "png": contentType = "image/png"
            case "heic", "heif": contentType = "image/heic"
            default: contentType = "image/jpeg"
            }
            onEdited(data, contentType)
        }
    }
}

struct MessagePhotoView: View {
    @EnvironmentObject private var state: AppState
    let messageID: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: 280, minHeight: 120, maxHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: messageID) {
            guard let data = try? await state.messagePhotoData(messageID: messageID) else { return }
            image = UIImage(data: data)
        }
        .accessibilityLabel("Annotated patient photo")
    }
}
