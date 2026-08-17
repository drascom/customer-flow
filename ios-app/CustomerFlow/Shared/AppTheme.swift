import SwiftUI
import UIKit
import PencilKit

struct RevealablePasswordField<FocusValue: Hashable>: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private let textContentType: UITextContentType?
    private let focusBinding: FocusState<FocusValue?>.Binding?
    private let focusValue: FocusValue?
    private let submitLabel: SubmitLabel
    private let onSubmit: () -> Void

    @State private var showsPassword = false
    @FocusState private var isInternallyFocused: Bool

    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        textContentType: UITextContentType? = .password,
        focus: FocusState<FocusValue?>.Binding,
        equals focusValue: FocusValue,
        submitLabel: SubmitLabel = .done,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.title = title
        _text = text
        self.textContentType = textContentType
        focusBinding = focus
        self.focusValue = focusValue
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 8) {
            focusedPasswordInput
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)

            Button {
                showsPassword.toggle()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
    }

    @ViewBuilder
    private var focusedPasswordInput: some View {
        if let focusBinding, let focusValue {
            passwordInput
                .focused(focusBinding, equals: focusValue)
        } else {
            passwordInput
                .focused($isInternallyFocused)
        }
    }

    @ViewBuilder
    private var passwordInput: some View {
        if showsPassword {
            TextField(title, text: $text)
        } else {
            SecureField(title, text: $text)
        }
    }
}

extension RevealablePasswordField where FocusValue == Bool {
    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        textContentType: UITextContentType? = .password,
        submitLabel: SubmitLabel = .done,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.title = title
        _text = text
        self.textContentType = textContentType
        focusBinding = nil
        focusValue = nil
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }
}

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
    static let opaqueSurface = adaptive(
        light: UIColor(white: 1, alpha: 1),
        dark: UIColor(red: 20 / 255, green: 14 / 255, blue: 10 / 255, alpha: 1)
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

struct PhotoUnavailableView: View {
    var body: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.title2)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.inset)
            .accessibilityLabel("Photo unavailable")
    }
}

struct NoPhotosView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
            Text("No photos uploaded")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.inset)
        .accessibilityLabel("No patient photos uploaded")
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
    @State private var isLoading = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .accessibilityLabel("Patient photo \(index + 1)")
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppTheme.inset)
                    } else {
                        PhotoUnavailableView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                if image != nil, let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.red.opacity(0.88), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("Remove photo \(index + 1)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard image != nil else { return }
            onTap?()
        }
        .task(id: "\(photoID ?? "missing"):\(reloadToken)") {
            image = nil
            isLoading = true
            guard let photoID else {
                isLoading = false
                return
            }
            guard let data = try? await state.photoData(photoID: photoID),
                  let loaded = UIImage(data: data) else {
                isLoading = false
                return
            }
            image = loaded
            isLoading = false
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
            .appendingPathComponent("CustomerFlowPhotoPreview", isDirectory: true)
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

private struct PhotoEditorRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let position: Int
}

struct NativePhotoPreview: View {
    let request: NativePhotoPreviewRequest
    let onEdited: (Data, String, String) async -> Bool
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var showsThumbnails = false
    @State private var editorRequest: PhotoEditorRequest?

    init(
        request: NativePhotoPreviewRequest,
        onEdited: @escaping (Data, String, String) async -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.onEdited = onEdited
        self.onClose = onClose
        _selectedIndex = State(initialValue: request.initialIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            if showsThumbnails { thumbnailStrip }
            TabView(selection: $selectedIndex) {
                ForEach(request.fileURLs.indices, id: \.self) { index in
                    PreviewPhotoPage(url: request.fileURLs[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            previewActions
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .fullScreenCover(item: $editorRequest) { item in
            PhotoMarkupEditor(
                image: item.image,
                position: item.position,
                onSend: { data, contentType, note in
                    let sent = await onEdited(data, contentType, note)
                    if sent {
                        editorRequest = nil
                        onClose()
                    }
                    return sent
                },
                onCancel: { editorRequest = nil }
            )
            .ignoresSafeArea()
        }
    }

    private var previewHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsThumbnails.toggle() }
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            Spacer()
            Text("\(selectedIndex + 1) / \(request.fileURLs.count)")
                .font(.headline.monospacedDigit())
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.94))
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(request.fileURLs.indices, id: \.self) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedIndex = index }
                    } label: {
                        if let image = UIImage(contentsOfFile: request.fileURLs[index].path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(index == selectedIndex ? Color.orange : .clear, lineWidth: 3)
                                }
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(.black.opacity(0.65), in: Circle())
                                        .padding(4)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.88))
    }

    private var previewActions: some View {
        HStack(spacing: 12) {
            if request.allowsEditing {
                Button {
                    guard request.fileURLs.indices.contains(selectedIndex),
                          let image = UIImage(contentsOfFile: request.fileURLs[selectedIndex].path) else { return }
                    editorRequest = PhotoEditorRequest(image: image, position: selectedIndex)
                } label: {
                    Label("Edit Photo", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if request.fileURLs.indices.contains(selectedIndex) {
                ShareLink(item: request.fileURLs[selectedIndex]) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.headline)
        .tint(.orange)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.black.opacity(0.94))
    }
}

private struct PreviewPhotoPage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in scale = min(max(baseScale * value, 1), 5) }
                            .onEnded { _ in baseScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = scale > 1 ? 1 : 2
                            baseScale = scale
                        }
                    }
            }
        }
        .clipped()
        .background(Color.black)
    }
}

private struct PhotoMarkupEditor: UIViewControllerRepresentable {
    let image: UIImage
    let position: Int
    let onSend: (Data, String, String) async -> Bool
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let editor = PhotoMarkupViewController(
            image: image,
            position: position,
            onSend: onSend,
            onCancel: onCancel
        )
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.navigationBar.prefersLargeTitles = false
        return navigationController
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

private final class PhotoTextView: UITextView {
    var currentFontSize: CGFloat = 32
    var pinchStartFontSize: CGFloat = 32
    var resizeStartFontSize: CGFloat = 32
    let resizeHandle = UIImageView()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        resizeHandle.image = UIImage(
            systemName: "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )
        resizeHandle.tintColor = .white
        resizeHandle.backgroundColor = .systemOrange
        resizeHandle.contentMode = .center
        resizeHandle.layer.cornerRadius = 12
        resizeHandle.isUserInteractionEnabled = true
        resizeHandle.accessibilityLabel = "Resize text"
        addSubview(resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeHandle.frame = CGRect(
            x: bounds.width - 28,
            y: bounds.height - 28,
            width: 24,
            height: 24
        )
        bringSubviewToFront(resizeHandle)
    }
}

private final class PhotoMarkupViewController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    private let sourceImage: UIImage
    private let position: Int
    private let onSend: (Data, String, String) async -> Bool
    private let onCancel: () -> Void
    private let imageView = UIImageView()
    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var textViews: [PhotoTextView] = []
    private var sendButton: UIButton!

    init(
        image: UIImage,
        position: Int,
        onSend: @escaping (Data, String, String) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        sourceImage = image
        self.position = position
        self.onSend = onSend
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let closeButton = controlButton(
            title: "",
            image: "xmark",
            action: #selector(cancel)
        )
        closeButton.configuration?.title = nil
        closeButton.configuration?.imagePadding = 0
        let textButton = controlButton(
            title: "Text",
            image: "textformat",
            action: #selector(addText)
        )
        let undoButton = controlButton(
            title: "Undo",
            image: "arrow.uturn.backward",
            action: #selector(undoDrawing)
        )
        compactTitle(on: undoButton)
        compactTitle(on: textButton)
        let controls = UIStackView(arrangedSubviews: [closeButton, undoButton, textButton])
        controls.axis = .horizontal
        controls.distribution = .fill
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        undoButton.widthAnchor.constraint(equalTo: textButton.widthAnchor).isActive = true

        let controlsBackground = glassControlsBackground()
        controlsBackground.translatesAutoresizingMaskIntoConstraints = false
        controlsBackground.contentView.addSubview(controls)
        view.addSubview(controlsBackground)

        sendButton = makeSendButton()
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sendButton)

        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)
        toolPicker.showsDrawingPolicyControls = false

        NSLayoutConstraint.activate([
            controlsBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            controlsBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controlsBackground.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -8),
            controlsBackground.heightAnchor.constraint(equalToConstant: 58),
            sendButton.centerYAnchor.constraint(equalTo: controlsBackground.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 88),
            sendButton.heightAnchor.constraint(equalToConstant: 52),
            controls.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor, constant: 6),
            controls.leadingAnchor.constraint(equalTo: controlsBackground.contentView.leadingAnchor, constant: 6),
            controls.trailingAnchor.constraint(equalTo: controlsBackground.contentView.trailingAnchor, constant: -6),
            controls.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor, constant: -6),
            imageView.topAnchor.constraint(equalTo: controlsBackground.bottomAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
        let preferredControlsWidth = controlsBackground.widthAnchor.constraint(equalToConstant: 260)
        preferredControlsWidth.priority = .defaultHigh
        preferredControlsWidth.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        toolPicker.removeObserver(canvasView)
        super.viewWillDisappear(animated)
    }

    private func controlButton(title: String, image: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .clearGlass()
        } else {
            configuration = .tinted()
        }
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeSendButton() -> UIButton {
        let button = UIButton(type: .system)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .filled()
        }
        configuration.title = "Send"
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemTeal
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(send), for: .touchUpInside)
        return button
    }

    private func compactTitle(on button: UIButton) {
        button.configuration?.imagePadding = 3
        button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .medium
        )
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
    }

    private func glassControlsBackground() -> UIVisualEffectView {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = UIColor.white.withAlphaComponent(0.2)
            glass.isInteractive = true
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        }
        let background = UIVisualEffectView(effect: effect)
        background.layer.cornerRadius = 29
        background.clipsToBounds = true
        return background
    }

    @objc private func undoDrawing() {
        canvasView.undoManager?.undo()
        canvasView.becomeFirstResponder()
    }

    @objc private func focusCanvas() {
        canvasView.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
    }

    @objc private func addText() {
        view.layoutIfNeeded()
        let textView = PhotoTextView()
        textView.delegate = self
        textView.textColor = .white
        textView.tintColor = .systemOrange
        textView.font = .systemFont(ofSize: textView.currentFontSize, weight: .semibold)
        textView.textAlignment = .center
        textView.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        textView.layer.cornerRadius = 10
        textView.layer.borderColor = UIColor.systemOrange.cgColor
        textView.layer.borderWidth = 2
        textView.clipsToBounds = true
        textView.isScrollEnabled = false
        textView.panGestureRecognizer.isEnabled = false
        textView.keyboardAppearance = .dark
        textView.autocapitalizationType = .sentences
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 26, right: 28)
        textView.textContainer.lineFragmentPadding = 0
        textView.inputAccessoryView = makeTextKeyboardAccessory()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveText(_:)))
        pan.delegate = self
        textView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(resizeText(_:)))
        pinch.delegate = self
        textView.addGestureRecognizer(pinch)
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(resizeTextFromCorner(_:)))
        resizePan.delegate = self
        textView.resizeHandle.addGestureRecognizer(resizePan)
        pan.require(toFail: resizePan)

        textView.frame = CGRect(origin: .zero, size: CGSize(width: 160, height: 58))
        let imageRect = aspectFitRect(for: sourceImage.size, in: canvasView.bounds)
        textView.center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        canvasView.addSubview(textView)
        textViews.append(textView)
        canvasView.undoManager?.registerUndo(withTarget: self) { target in
            target.removeTextView(textView)
        }
        textView.becomeFirstResponder()
    }

    @objc private func finishTextEditing() {
        view.endEditing(true)
        focusCanvas()
    }

    private func makeTextKeyboardAccessory() -> UIView {
        let accessory = UIView(
            frame: CGRect(x: 0, y: 0, width: max(view.bounds.width, 320), height: 68)
        )
        accessory.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        accessory.autoresizingMask = [.flexibleWidth]

        let doneButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Done"
        configuration.image = UIImage(systemName: "checkmark")
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemTeal
        doneButton.configuration = configuration
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(finishTextEditing), for: .touchUpInside)
        accessory.addSubview(doneButton)

        NSLayoutConstraint.activate([
            doneButton.centerXAnchor.constraint(equalTo: accessory.centerXAnchor),
            doneButton.centerYAnchor.constraint(equalTo: accessory.centerYAnchor, constant: -2),
            doneButton.widthAnchor.constraint(equalToConstant: 200),
            doneButton.heightAnchor.constraint(equalToConstant: 46)
        ])
        return accessory
    }

    private func removeTextView(_ textView: PhotoTextView) {
        textViews.removeAll { $0 === textView }
        textView.removeFromSuperview()
    }

    @objc private func moveText(_ gesture: UIPanGestureRecognizer) {
        guard let textView = gesture.view as? PhotoTextView else { return }
        let translation = gesture.translation(in: canvasView)
        textView.center = CGPoint(
            x: textView.center.x + translation.x,
            y: textView.center.y + translation.y
        )
        keepTextInsideImage(textView)
        gesture.setTranslation(.zero, in: canvasView)
    }

    @objc private func resizeText(_ gesture: UIPinchGestureRecognizer) {
        guard let textView = gesture.view as? PhotoTextView else { return }
        if gesture.state == .began {
            textView.pinchStartFontSize = textView.currentFontSize
        }
        textView.currentFontSize = min(max(textView.pinchStartFontSize * gesture.scale, 16), 96)
        textView.font = .systemFont(ofSize: textView.currentFontSize, weight: .semibold)
        resizeTextViewToFit(textView)
    }

    @objc private func resizeTextFromCorner(_ gesture: UIPanGestureRecognizer) {
        guard let handle = gesture.view,
              let textView = handle.superview as? PhotoTextView else { return }
        if gesture.state == .began {
            textView.resizeStartFontSize = textView.currentFontSize
        }
        let translation = gesture.translation(in: canvasView)
        let diagonalChange = (translation.x + translation.y) / 2
        textView.currentFontSize = min(
            max(textView.resizeStartFontSize + diagonalChange * 0.35, 16),
            96
        )
        textView.font = .systemFont(ofSize: textView.currentFontSize, weight: .semibold)
        resizeTextViewToFit(textView)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        textView.layer.borderWidth = 2
        toolPicker.setVisible(false, forFirstResponder: canvasView)
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let textView = textView as? PhotoTextView else { return }
        resizeTextViewToFit(textView)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard let textView = textView as? PhotoTextView else { return }
        textView.layer.borderWidth = 0
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeTextView(textView)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView = gestureRecognizer.view as? PhotoTextView else { return true }
        if gestureRecognizer is UIPanGestureRecognizer {
            return !textView.isFirstResponder
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
    }

    private func resizeTextViewToFit(_ textView: PhotoTextView) {
        let center = textView.center
        let imageRect = aspectFitRect(for: sourceImage.size, in: canvasView.bounds)
        let maximumWidth = max(imageRect.width * 0.86, 120)
        let displayText = textView.text.isEmpty ? "Type here" : textView.text ?? ""
        let horizontalInsets = textView.textContainerInset.left + textView.textContainerInset.right
        let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let textBounds = (displayText as NSString).boundingRect(
            with: CGSize(width: maximumWidth - horizontalInsets, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textView.font as Any],
            context: nil
        )
        textView.bounds.size = CGSize(
            width: min(max(ceil(textBounds.width) + horizontalInsets, 120), maximumWidth),
            height: max(ceil(textBounds.height) + verticalInsets, 58)
        )
        textView.center = center
        keepTextInsideImage(textView)
    }

    private func keepTextInsideImage(_ textView: PhotoTextView) {
        let imageRect = aspectFitRect(for: sourceImage.size, in: canvasView.bounds)
        let horizontalInset = min(textView.bounds.width / 2, imageRect.width / 2)
        let verticalInset = min(textView.bounds.height / 2, imageRect.height / 2)
        textView.center = CGPoint(
            x: min(max(textView.center.x, imageRect.minX + horizontalInset), imageRect.maxX - horizontalInset),
            y: min(max(textView.center.y, imageRect.minY + verticalInset), imageRect.maxY - verticalInset)
        )
    }

    @objc private func cancel() {
        onCancel()
    }

    @objc private func send() {
        view.endEditing(true)
        let alert = UIAlertController(
            title: "Send edited photo",
            message: "Add a note for the conversation, or send the photo without one.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Note (optional)"
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send Photo", style: .default) { [weak self, weak alert] _ in
            self?.renderAndSend(note: alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func renderAndSend(note: String) {
        view.layoutIfNeeded()
        let imageRect = aspectFitRect(for: sourceImage.size, in: canvasView.bounds)
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        let drawingScale = sourceImage.size.width / imageRect.width
        let drawingImage = canvasView.drawing.image(from: imageRect, scale: drawingScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: sourceImage.size, format: format)
        let handleVisibility = textViews.map { $0.resizeHandle.isHidden }
        textViews.forEach { $0.resizeHandle.isHidden = true }
        let markedImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: sourceImage.size))
            drawingImage.draw(in: CGRect(origin: .zero, size: sourceImage.size))
            for textView in textViews {
                let frame = CGRect(
                    x: (textView.frame.minX - imageRect.minX) * drawingScale,
                    y: (textView.frame.minY - imageRect.minY) * drawingScale,
                    width: textView.frame.width * drawingScale,
                    height: textView.frame.height * drawingScale
                )
                textView.drawHierarchy(in: frame, afterScreenUpdates: true)
            }
        }
        for (index, textView) in textViews.enumerated() {
            textView.resizeHandle.isHidden = handleVisibility[index]
        }
        guard let data = markedImage.jpegData(compressionQuality: 0.92) else { return }
        sendButton.isEnabled = false
        sendButton.configuration?.showsActivityIndicator = true
        Task { [weak self] in
            guard let self else { return }
            let sent = await onSend(data, "image/jpeg", note)
            guard !sent else { return }
            sendButton.isEnabled = true
            sendButton.configuration?.showsActivityIndicator = false
            let error = UIAlertController(
                title: "Photo not sent",
                message: "Please check the connection and try again.",
                preferredStyle: .alert
            )
            error.addAction(UIAlertAction(title: "OK", style: .default))
            present(error, animated: true)
        }
    }

    private func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
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

struct LatestMessagePreview: View {
    let author: String
    let text: String
    let createdAt: Date
    let hasPhoto: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: hasPhoto ? "photo" : "bubble.left")
                .foregroundStyle(AppTheme.brand)
            (
                Text(author).fontWeight(.semibold)
                + Text("  \(previewText)")
            )
            .foregroundStyle(AppTheme.ink)
            .lineLimit(1)
            Spacer(minLength: 6)
            Text(dayRelativeText)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private var previewText: String {
        if hasPhoto { return "Photo sent" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New reply" : trimmed
    }

    private var dayRelativeText: String {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: createdAt)
        let startToday = calendar.startOfDay(for: Date())
        let days = max(0, calendar.dateComponents([.day], from: startDate, to: startToday).day ?? 0)

        return switch days {
        case 0: "Today"
        case 1: "Yesterday"
        default: "\(days) days ago"
        }
    }
}

extension Date {
    var compactRelativeText: String {
        let elapsed = max(0, Int(Date.now.timeIntervalSince(self)))
        let roundedMinutes = Int((Double(elapsed) / 60).rounded())
        guard roundedMinutes > 0 else { return "Now" }
        guard roundedMinutes >= 60 else { return "\(roundedMinutes) min" }

        let roundedHours = Int((Double(elapsed) / 3_600).rounded())
        guard roundedHours >= 24 else { return "\(roundedHours) hr" }

        let roundedDays = max(1, Int((Double(elapsed) / 86_400).rounded()))
        return roundedDays == 1 ? "1 day" : "\(roundedDays) days"
    }
}
