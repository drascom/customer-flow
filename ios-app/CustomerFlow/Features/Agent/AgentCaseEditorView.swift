import PhotosUI
import SwiftUI
import UIKit

private enum AgentCaseFilter: String, CaseIterable, Identifiable {
    case all
    case waiting
    case answered
    case closed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All cases"
        case .waiting: "Waiting for Doctor"
        case .answered: "Waiting for Me"
        case .closed: "Closed"
        }
    }
}

struct AgentCasesView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: AgentCaseFilter = .all
    @State private var searchText = ""

    private var myCases: [ConsultationCase] {
        state.cases
            .filter { $0.agentName == state.currentAgentName }
            .filter { item in
                switch filter {
                case .all: true
                case .waiting: item.status == .waiting
                case .answered: item.status == .answered
                case .closed: item.status == .closed
                }
            }
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [item.patient.name, item.reference, item.agentNote]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.uploadedAt > $1.uploadedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            filterMenu
                            NavigationLink {
                                AgentCaseEditorView()
                            } label: {
                                Label("New", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .background(AppTheme.surfaceStrong, in: Capsule())
                                    .overlay(Capsule().stroke(AppTheme.border))
                            }
                            .buttonStyle(.plain)
                        }

                        if myCases.isEmpty {
                            ContentUnavailableView("No cases", systemImage: "tray", description: Text("No cases match this view."))
                                .frame(minHeight: 300)
                        } else {
                            ForEach(myCases) { item in
                                NavigationLink {
                                    AgentCaseEditorView(caseID: item.id)
                                } label: {
                                    AgentCaseListCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                } header: {
                    searchHeader
                }
            }
        }
        .background(AppTheme.background)
        .refreshable { await state.load() }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.muted)
            TextField("Search my cases", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceStrong)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(AgentCaseFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Label("\(item.title) · \(count(for: item))", systemImage: filter == item ? "checkmark" : "circle")
                }
            }
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    Text(filter.title)
                    Text("\(count(for: filter))")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentInk.opacity(0.12), in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentInk)
            .padding(.horizontal, 14)
            .frame(minWidth: 190, maxWidth: .infinity, minHeight: 40)
            .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: AgentCaseFilter) -> Int {
        state.cases.filter { item in
            guard item.agentName == state.currentAgentName else { return false }
            switch filter {
            case .all: return true
            case .waiting: return item.status == .waiting
            case .answered: return item.status == .answered
            case .closed: return item.status == .closed
            }
        }.count
    }
}

private struct AgentCaseListCard: View {
    let item: ConsultationCase
    @State private var photoIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.uploadedAt.formatted(.relative(presentation: .named)))
                Spacer()
                Text(item.reference).fontWeight(.bold)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.muted)

            TabView(selection: $photoIndex) {
                ForEach(0..<item.photoCount, id: \.self) { index in
                    CasePhotoView(
                        photoID: item.photoIDs.indices.contains(index) ? item.photoIDs[index] : nil,
                        index: index
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .bottomTrailing) {
                Text("\(photoIndex + 1) / \(item.photoCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(9)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(item.patient.name)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                AgentStatusChip(status: item.status)
            }

            Text(item.agentNote)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)

            HStack {
                Label("\(item.agentGrafts) grafts", systemImage: "scissors")
                Spacer()
                Text(AppCurrency.amount(item.agentPrice))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.brandDark)

            if let latestMessage {
                Divider()
                LatestMessagePreview(
                    author: latestMessage.author,
                    text: latestMessage.text,
                    createdAt: latestMessage.createdAt,
                    hasPhoto: latestMessage.attachmentPhotoID != nil
                )
            }
        }
        .padding(14)
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
    }

    private var latestMessage: ConsultationMessage? {
        item.messages.last { $0.role != .system }
    }
}

private struct AgentStatusChip: View {
    let status: ConsultationStatus

    private var color: Color {
        switch status {
        case .waiting: AppTheme.accent
        case .answered: AppTheme.brand
        case .closed: AppTheme.muted
        }
    }

    var body: some View {
        Text(status == .answered ? "Action needed" : status.title)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct AgentCaseEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var editingCaseID: UUID?
    @State private var detailsExpanded: Bool
    @State private var patientName = ""
    @State private var grafts = "3,200"
    @State private var currency = AppCurrency.code
    @State private var price = "2,850"
    @State private var agentNote = ""
    @State private var updateText = ""
    @State private var photoCount: Int
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [CasePhotoUpload] = []
    @State private var isImportingPhotos = false
    @State private var photoReloadToken = 0
    @State private var pendingPhotoDeletionID: String?
    @State private var pendingMessageDeletion: ConsultationMessage?
    @State private var photoPreview: NativePhotoPreviewRequest?
    @State private var matchCandidate: PatientMatchCandidate?
    @State private var duplicateResolution: DuplicateResolution?
    @State private var statusText = "Draft · Not saved"
    @State private var returnedToDoctor = false
    @State private var createStep: CreateStep = .patient
    @State private var patientVerification: PatientVerification = .idle
    @State private var isSubmitting = false

    init(caseID: UUID? = nil) {
        _editingCaseID = State(initialValue: caseID)
        _detailsExpanded = State(initialValue: caseID == nil)
        _photoCount = State(initialValue: caseID == nil ? 0 : 3)
    }

    private enum DuplicateResolution { case existing, different }
    private enum PatientVerification { case idle, checking, matchFound, newPatient, differentConfirmed, existingSelected }
    private enum CreateStep: Int, CaseIterable {
        case patient
        case needs
        case plan
        case photos

        var title: String {
            switch self {
            case .patient: "Patient"
            case .needs: "Needs"
            case .plan: "Graft & price"
            case .photos: "Photos"
            }
        }
    }

    private var isEditMode: Bool { editingCaseID != nil }

    private var editCase: ConsultationCase? {
        guard let editingCaseID else { return nil }
        return state.cases.first { $0.id == editingCaseID }
    }

    private var missingItems: [String] {
        var result: [String] = []
        if patientName.trimmingCharacters(in: .whitespaces).isEmpty { result.append("patient name") }
        if grafts.trimmingCharacters(in: .whitespaces).isEmpty { result.append("graft number") }
        if price.trimmingCharacters(in: .whitespaces).isEmpty { result.append("price") }
        if agentNote.trimmingCharacters(in: .whitespaces).isEmpty { result.append("agent note") }
        if photoCount < 2 { result.append("at least 2 photos") }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isEditMode {
                    caseDetails
                    patientPhotos
                } else {
                    createStepContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .onAppear(perform: configureForm)
        .sheet(item: $matchCandidate) { candidate in
            PatientMatchSheet(
                candidate: candidate,
                onOpenExisting: { useExistingPatient(candidate) },
                onSamePatient: { endDuplicateRegistration() },
                onDifferentPatient: {
                    duplicateResolution = .different
                    patientVerification = .differentConfirmed
                    statusText = "Different patient confirmed · New Patient ID"
                }
            )
            .presentationDetents([.large])
        }
        .task(id: patientName) {
            guard !isEditMode else { return }
            duplicateResolution = nil
            patientVerification = .idle
            guard patientName.split(whereSeparator: \.isWhitespace).count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            patientVerification = .checking
            await checkForExistingPatient()
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fullScreenCover(item: $photoPreview) { request in
            NativePhotoPreview(request: request) { data, contentType in
                Task { await sendAnnotatedPhoto(data, contentType: contentType, caseID: request.caseID) }
            } onClose: {
                photoPreview = nil
            }
        }
        .confirmationDialog(
            "Remove this photo?",
            isPresented: Binding(
                get: { pendingPhotoDeletionID != nil },
                set: { if !$0 { pendingPhotoDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove photo", role: .destructive) {
                guard let photoID = pendingPhotoDeletionID else { return }
                pendingPhotoDeletionID = nil
                Task { await removePhoto(photoID) }
            }
            Button("Cancel", role: .cancel) { pendingPhotoDeletionID = nil }
        } message: {
            Text("The photo will disappear for agents and doctors, but administrators will retain access to the original file.")
        }
        .confirmationDialog(
            "Remove this comment?",
            isPresented: Binding(
                get: { pendingMessageDeletion != nil },
                set: { if !$0 { pendingMessageDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove comment", role: .destructive) {
                guard let message = pendingMessageDeletion, let caseID = editingCaseID else { return }
                pendingMessageDeletion = nil
                Task { _ = await state.deleteMessage(caseID: caseID, messageID: message.id) }
            }
            Button("Cancel", role: .cancel) { pendingMessageDeletion = nil }
        } message: {
            Text("The comment will disappear from the conversation, but administrators will retain the record.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Cases", systemImage: "chevron.left") { dismiss() }
                .font(.caption.weight(.semibold))

            if isEditMode {
                HStack(spacing: 10) {
                    Text("Edit case")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if let editCase {
                        Text(editCase.reference)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Label(statusText, systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(returnedToDoctor ? .orange : .blue)
            } else {
                Text("Create case")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .center)

                createProgress
            }
        }
    }

    private var createProgress: some View {
        HStack(spacing: 10) {
            Text("\(createStep.rawValue + 1)/\(CreateStep.allCases.count) · \(createStep.title)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            ProgressView(value: Double(createStep.rawValue + 1), total: Double(CreateStep.allCases.count))
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var createStepContent: some View {
        switch createStep {
        case .patient:
            wizardCard("Patient") {
                labeledField("Patient name", required: true) {
                    TextField("Enter the patient's full name", text: $patientName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                }
                patientVerificationView
                    .font(.caption)
            }
        case .needs:
            wizardCard("Needs") {
                Text("Patient note *")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                TextField("Hair loss pattern, expectations and question for the doctor", text: $agentNote, axis: .vertical)
                    .font(.body)
                    .lineLimit(7...11)
                    .textFieldStyle(.roundedBorder)
            }
        case .plan:
            wizardCard("Graft & price", info: "Enter your estimated graft number and proposed price. You can revise these values after the doctor provides their recommendation.") {
                labeledField("Estimated graft number", required: true) {
                    TextField("3,200", text: $grafts)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Estimated price", required: true) {
                    HStack(spacing: 8) {
                        Text(AppCurrency.symbol)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        TextField("2,850", text: $price)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        case .photos:
            wizardCard("Photos", info: "At least two photos are required.") {
                HStack {
                    Text("\(photoCount) photos")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.brandDark)
                    Spacer()
                    Text(photoCount >= 2 ? "Ready" : "Minimum 2")
                        .font(.caption)
                        .foregroundStyle(photoCount >= 2 ? AppTheme.brandDark : AppTheme.accent)
                }

                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                    Label("Add photos", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)

                if isImportingPhotos {
                    ProgressView("Preparing photos…")
                        .font(.caption)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(Array(pendingPhotos.enumerated()), id: \.element.id) { index, photo in
                        PendingPhotoThumbnail(photo: photo, index: index)
                            .frame(height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var patientVerificationView: some View {
        switch patientVerification {
        case .idle:
            Label("Enter first and last name to check records.", systemImage: "person.text.rectangle")
                .foregroundStyle(AppTheme.muted)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking patient records…")
            }
            .foregroundStyle(AppTheme.muted)
        case .matchFound:
            Label("Possible patient found. Complete the identity confirmation.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.accent)
        case .newPatient:
            Label("No matching patient found.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.brandDark)
        case .differentConfirmed:
            Label("Different patient confirmed.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.brandDark)
        case .existingSelected:
            Label("Existing patient selected.", systemImage: "person.crop.circle.badge.checkmark")
                .foregroundStyle(AppTheme.brandDark)
        }
    }

    private func wizardCard<Content: View>(_ title: String, info: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            content()
            if let info {
                Divider()
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted.opacity(0.76))
            }
        }
        .font(.subheadline)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private var caseDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(patientName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button(detailsExpanded ? "Done" : "Edit", systemImage: detailsExpanded ? "checkmark" : "pencil") {
                    withAnimation(.easeInOut(duration: 0.2)) { detailsExpanded.toggle() }
                }
                .font(.caption.weight(.semibold))
            }

            Text(agentNote)
                .font(.body)
                .foregroundStyle(AppTheme.ink.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                summaryMetric("Grafts", grafts)
                summaryMetric("Price", AppCurrency.amount(price))
            }

            if detailsExpanded {
                Divider()
                VStack(spacing: 12) {
                    labeledField("Patient name", required: true) {
                        TextField("Patient name", text: $patientName)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 10) {
                        labeledField("Grafts", required: true) {
                            TextField("3,200", text: $grafts)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Price", required: true) {
                            HStack(spacing: 6) {
                                Text(AppCurrency.symbol)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                TextField("2,850", text: $price)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.brandDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 10))
    }

    private var patientPhotos: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos").font(.headline)
                Spacer()
                Text("\(photoCount) photos")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                Label("Add photos", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isImportingPhotos {
                ProgressView("Uploading photos…")
                    .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(0..<photoCount, id: \.self) { index in
                    let photoID = editCase?.photoIDs.indices.contains(index) == true ? editCase?.photoIDs[index] : nil
                    CasePhotoView(
                        photoID: photoID,
                        index: index,
                        reloadToken: photoReloadToken,
                        onDelete: photoDeleteAction(for: photoID),
                        onTap: photoPreviewAction(for: photoID)
                    )
                        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                                .padding(6)
                        }
                }
            }

            if isEditMode, let editCase {
                Divider()
                Text("Conversation").font(.headline)
                ForEach(editCase.messages) { message in
                    MessagePreview(
                        message: message,
                        canDelete: message.authorID == state.currentUser?.id,
                        onDelete: { pendingMessageDeletion = message }
                    )
                }
                labeledField("Add an update or question", required: false) {
                    TextField("Write a follow-up for the assigned doctor", text: $updateText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }
                if !updateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Send to doctor") {
                        Task {
                            if await state.sendAgentUpdate(caseID: editCase.id, text: updateText) {
                                updateText = ""
                                returnedToDoctor = true
                                statusText = "Waiting for Doctor · Update sent"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private func photoDeleteAction(for photoID: String?) -> (() -> Void)? {
        guard let photoID else { return nil }
        return { pendingPhotoDeletionID = photoID }
    }

    private func photoPreviewAction(for photoID: String?) -> (() -> Void)? {
        guard let photoID, let editingCaseID else { return nil }
        return { Task { await openNativePreview(photoID: photoID, caseID: editingCaseID) } }
    }

    @MainActor
    private func openNativePreview(photoID: String, caseID: UUID) async {
        do {
            guard let editCase else { return }
            let photoIDs = editCase.photoIDs
            var photoData: [String: Data] = [:]
            for itemID in photoIDs {
                photoData[itemID] = try await state.photoData(photoID: itemID)
            }
            photoPreview = try NativePhotoPreviewRequest.make(
                caseID: caseID,
                photoIDs: photoIDs,
                photoData: photoData,
                initialIndex: photoIDs.firstIndex(of: photoID) ?? 0,
                allowsEditing: true
            )
        } catch {
            state.errorMessage = "The photo could not be opened."
        }
    }

    @MainActor
    private func sendAnnotatedPhoto(_ data: Data, contentType: String, caseID: UUID) async {
        statusText = "Sending annotated photo…"
        if await state.sendPhotoMessage(caseID: caseID, data: data, contentType: contentType) {
            statusText = "Waiting for Doctor · Annotated photo sent"
            returnedToDoctor = true
        } else {
            statusText = "Annotated photo could not be sent"
        }
    }

    @MainActor
    private func removePhoto(_ photoID: String) async {
        guard let editingCaseID else { return }
        statusText = "Removing photo…"
        if await state.deletePhoto(caseID: editingCaseID, photoID: photoID) {
            photoCount = state.cases.first(where: { $0.id == editingCaseID })?.photoCount ?? max(0, photoCount - 1)
            photoReloadToken += 1
            returnedToDoctor = true
            statusText = "Waiting for Doctor · Photo removed"
        } else {
            statusText = "Photo removal failed · Try again"
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if isEditMode {
            if detailsExpanded || (editCase?.status == .answered && !returnedToDoctor) {
                editActionBar
            }
        } else {
            wizardActionBar
        }
    }

    private var editActionBar: some View {
        Group {
            if detailsExpanded {
                Button("Save changes") {
                    if let editCase {
                        Task {
                            if await state.saveAgentValues(caseID: editCase.id, patientName: patientName, grafts: grafts, currency: currency, price: price) {
                                statusText = "Changes saved"
                                detailsExpanded = false
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if editCase?.status == .answered && !returnedToDoctor {
                Button("Confirm & Close") {
                    if let editCase {
                        Task { if await state.confirmAndClose(caseID: editCase.id) { statusText = "Closed" } }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceStrong)
    }

    private var wizardActionBar: some View {
        HStack(spacing: 10) {
            if createStep != .patient {
                Button("Back") {
                    if let previous = CreateStep(rawValue: createStep.rawValue - 1) {
                        createStep = previous
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if isSubmitting {
                ProgressView()
            } else if canAdvance {
                Button(createStep == .photos ? "Submit" : "Continue") {
                    if createStep == .photos {
                        submitNewCase()
                    } else if let next = CreateStep(rawValue: createStep.rawValue + 1) {
                        createStep = next
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceStrong)
    }

    private var canAdvance: Bool {
        switch createStep {
        case .patient:
            return patientVerification == .newPatient || patientVerification == .differentConfirmed
        case .needs:
            return !agentNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .plan:
            return !grafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            return missingItems.isEmpty
        }
    }

    private func submitNewCase() {
        guard canAdvance, !isSubmitting else { return }
        isSubmitting = true
        Task {
            let created = await state.createCase(
                patientName: patientName,
                grafts: grafts,
                currency: currency,
                price: price,
                note: agentNote,
                photos: pendingPhotos,
                duplicateConfirmedDifferent: duplicateResolution == .different
            )
            isSubmitting = false
            if created { dismiss() }
        }
    }

    private func configureForm() {
        returnedToDoctor = false
        duplicateResolution = nil
        if let item = editCase {
            detailsExpanded = false
            patientName = item.patient.name
            grafts = item.agentGrafts
            currency = AppCurrency.code
            price = item.agentPrice
            agentNote = item.agentNote
            photoCount = item.photoCount
            statusText = item.status.title
        } else {
            detailsExpanded = true
            patientName = ""
            grafts = "3,200"
            currency = AppCurrency.code
            price = "2,850"
            agentNote = ""
            photoCount = 0
            pendingPhotos = []
            createStep = .patient
            patientVerification = .idle
            statusText = "Draft · Not saved"
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !isImportingPhotos else { return }
        isImportingPhotos = true
        defer {
            isImportingPhotos = false
            selectedPhotos = []
        }

        var imported: [CasePhotoUpload] = []
        for item in items {
            do {
                guard let source = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: source),
                      let jpeg = image.jpegData(compressionQuality: 0.9) else {
                    throw PhotoImportError.unreadable
                }
                imported.append(CasePhotoUpload(data: jpeg, contentType: "image/jpeg"))
            } catch {
                state.errorMessage = "One or more selected photos could not be read."
            }
        }
        guard !imported.isEmpty else { return }

        if let editingCaseID {
            statusText = "Uploading photos…"
            if await state.uploadPhotos(caseID: editingCaseID, photos: imported) {
                photoCount = state.cases.first(where: { $0.id == editingCaseID })?.photoCount ?? photoCount
                photoReloadToken += 1
                returnedToDoctor = true
                statusText = "Waiting for Doctor · Photos uploaded"
            } else {
                statusText = "Photo upload failed · Try again"
            }
        } else {
            pendingPhotos.append(contentsOf: imported)
            photoCount = pendingPhotos.count
        }
    }

    private func checkForExistingPatient() async {
        guard duplicateResolution == nil else { return }
        do {
            if let first = try await state.patientMatcher.findMatches(for: patientName).first {
                patientVerification = .matchFound
                matchCandidate = first
            } else {
                patientVerification = .newPatient
                statusText = "New patient · Name verified"
            }
        } catch {
            patientVerification = .idle
            state.errorMessage = error.localizedDescription
        }
    }

    private func useExistingPatient(_ candidate: PatientMatchCandidate) {
        guard !candidate.createdByAnotherAgent else { return }
        duplicateResolution = .existing
        patientVerification = .existingSelected
        if let item = state.cases.first(where: { $0.patient.id == candidate.id }) {
            editingCaseID = item.id
            detailsExpanded = false
            patientName = item.patient.name
            grafts = item.agentGrafts
            currency = AppCurrency.code
            price = item.agentPrice
            agentNote = item.agentNote
            photoCount = item.photoCount
            statusText = "Existing patient · Assigned doctor preserved"
        } else {
            statusText = "Existing patient selected · Patient record preserved"
        }
    }

    private func endDuplicateRegistration() {
        duplicateResolution = .existing
        patientVerification = .matchFound
        statusText = "Consultation already exists · No case created"
        dismiss()
    }

    private func labeledField<Content: View>(_ title: String, required: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + (required ? " *" : ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PhotoImportError: Error {
    case unreadable
}

private struct PendingPhotoThumbnail: View {
    let photo: CasePhotoUpload
    let index: Int

    var body: some View {
        Group {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ClinicalPhotoPlaceholder(index: index)
            }
        }
        .clipped()
        .accessibilityLabel("Selected patient photo \(index + 1)")
    }
}

private struct MessagePreview: View {
    let message: ConsultationMessage
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(message.author).font(.caption.bold())
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Remove comment")
                }
                Text(message.createdAt, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
            }
            Text(message.text).font(.body)
            if let attachmentPhotoID = message.attachmentPhotoID {
                MessagePhotoView(messageID: attachmentPhotoID)
            }
            if let grafts = message.approximateGrafts, let price = message.recommendedPrice {
                Text("Approx. \(grafts) grafts · Recommended \(AppCurrency.amount(price))")
                    .font(.caption.bold()).foregroundStyle(AppTheme.brand)
            }
        }
        .padding(12)
        .background((message.role == .doctor ? AppTheme.brand : AppTheme.muted).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
