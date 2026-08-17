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
    @State private var selectedCaseID: UUID?

    private var myCases: [ConsultationCase] {
        state.cases
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
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .background(AppTheme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)

                        if myCases.isEmpty {
                            ContentUnavailableView("No cases", systemImage: "tray", description: Text("No cases match this view."))
                                .frame(minHeight: 300)
                                .padding(.horizontal, 12)
                        } else {
                            ForEach(myCases) { item in
                                AgentCaseListCard(
                                    item: item,
                                    onOpen: { selectedCaseID = item.id }
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.bottom, 18)
                } header: {
                    searchHeader
                }
            }
        }
        .background(AppTheme.background)
        .refreshable { await state.load() }
        .onChange(of: state.pendingNotificationCaseID) { _, caseID in
            guard let caseID, state.cases.contains(where: { $0.id == caseID }) else { return }
            selectedCaseID = caseID
            state.consumePendingNotificationCase()
        }
        .sheet(
            isPresented: Binding(
                get: { selectedCaseID != nil },
                set: { if !$0 { selectedCaseID = nil } }
            )
        ) {
            if let caseID = selectedCaseID {
                NavigationStack {
                    AgentCaseEditorView(caseID: caseID)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    selectedCaseID = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.subheadline.bold())
                                }
                                .accessibilityLabel("Close case details")
                            }
                        }
                        .toolbarBackground(AppTheme.opaqueSurface, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
                .presentationDetents([.fraction(0.97)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationContentInteraction(.scrolls)
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Search", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: 620, minHeight: 42)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.background)
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
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 14)
            .frame(minWidth: 190, maxWidth: .infinity, minHeight: 40)
            .background(AppTheme.surfaceStrong, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.border))
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: AgentCaseFilter) -> Int {
        state.cases.filter { item in
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
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.patient.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    statusChip
                }

                Divider()
                    .overlay(AppTheme.muted.opacity(0.22))

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(item.uploadedAt.compactRelativeText)
                    Spacer(minLength: 12)
                    Image(systemName: "person.crop.circle")
                    Text(item.agentName)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.muted)

                Text(item.agentNote)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.82))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    metric("Est. grafts", item.agentGrafts)
                    metric("Est. price", AppCurrency.amount(item.agentPrice))
                    metric("Media", "\(item.photoCount) · \(item.messages.count)")
                }

                if let finalGrafts = item.finalGrafts,
                   let finalPrice = item.finalPrice {
                    HStack(spacing: 8) {
                        metric("Final grafts", finalGrafts)
                        metric("Final price", AppCurrency.amount(finalPrice))
                    }
                }

                if let latestMessage {
                    Divider().padding(.vertical, 1)
                    LatestMessagePreview(
                        author: latestMessage.author,
                        text: latestMessage.text,
                        createdAt: latestMessage.createdAt,
                        hasPhoto: latestMessage.attachmentPhotoID != nil
                    )
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ink)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityHint("Opens case details")
    }

    private var statusChip: some View {
        Text(shortStatus)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.13), in: Capsule())
    }

    private var shortStatus: String {
        switch item.status {
        case .waiting: "Waiting for Doctor"
        case .answered: "Action needed"
        case .closed: "Confirmed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .waiting: AppTheme.accent
        case .answered: Color(red: 0.78, green: 0.16, blue: 0.14)
        case .closed: Color(red: 0.08, green: 0.52, blue: 0.32)
        }
    }

    private var latestMessage: ConsultationMessage? {
        item.messages.last { $0.role != .system }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AgentCaseEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var editingCaseID: UUID?
    @State private var detailsExpanded: Bool
    @State private var patientName = ""
    @State private var dateOfBirthText = ""
    @State private var patientAge = ""
    @State private var gender = ""
    @State private var patientPhone = ""
    @State private var patientEmail = ""
    @State private var patientAddress = ""
    @State private var occupation = ""
    @State private var profileNote = ""
    @State private var grafts = "3,200"
    @State private var currency = AppCurrency.code
    @State private var price = "2,850"
    @State private var finalGrafts = ""
    @State private var finalPrice = ""
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
    @State private var isMatchDetailsPresented = false
    @State private var duplicateResolution: DuplicateResolution?
    @State private var statusText = "Draft · Not saved"
    @State private var returnedToDoctor = false
    @State private var createStep: CreateStep = .patient
    @State private var patientVerification: PatientVerification = .idle
    @State private var isSubmitting = false
    @FocusState private var isPatientNameFocused: Bool

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

    private var canEditCase: Bool {
        guard let editCase else { return true }
        if let agentID = editCase.agentID {
            return agentID == state.currentUser?.id
        }
        return editCase.agentName == state.currentAgentName
    }

    private var editCase: ConsultationCase? {
        guard let editingCaseID else { return nil }
        return state.cases.first { $0.id == editingCaseID }
    }

    private var latestDoctorRecommendation: ConsultationMessage? {
        editCase?.messages.last {
            $0.role == .doctor
                && ($0.approximateGrafts != nil || $0.recommendedPrice != nil)
        }
    }

    private var finalPlanReady: Bool {
        !finalGrafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !finalPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    conversationSection
                    if let editCase,
                       editCase.status == .closed || (editCase.status == .answered && latestDoctorRecommendation != nil) {
                        finalPlanSection(editCase)
                    }
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
        .task {
            guard !isEditMode else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isPatientNameFocused = true
        }
        .sheet(isPresented: $isMatchDetailsPresented) {
            if let candidate = matchCandidate {
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
                .presentationDetents([.fraction(0.78)])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fullScreenCover(item: $photoPreview) { request in
            NativePhotoPreview(request: request) { data, contentType, note in
                await sendAnnotatedPhoto(
                    data, contentType: contentType, note: note, caseID: request.caseID
                )
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
        Group {
            if !isEditMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create case")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)

                    createProgress
                }
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
                        .submitLabel(.done)
                        .focused($isPatientNameFocused)
                        .onSubmit { isPatientNameFocused = false }
                        .onChange(of: patientName) { _, _ in
                            guard !isEditMode, isPatientNameFocused else { return }
                            matchCandidate = nil
                            isMatchDetailsPresented = false
                            duplicateResolution = nil
                            patientVerification = .idle
                            statusText = "Draft · Not saved"
                        }
                        .onChange(of: isPatientNameFocused) { wasFocused, isFocused in
                            guard wasFocused, !isFocused, !isEditMode else { return }
                            Task { await verifyPatientNameAfterEditing() }
                        }
                }
                patientVerificationView
                    .font(.caption)
                Divider()
                patientProfileFields
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

                if photoCount > 0 {
                    PhotoSourceButton(
                        selectedPhotos: $selectedPhotos,
                        onCameraPhoto: importCameraPhoto
                    ) {
                        Label("Add photos", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.brand)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }

                if isImportingPhotos {
                    ProgressView("Preparing photos…")
                        .font(.caption)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    if pendingPhotos.isEmpty {
                        PhotoSourceButton(
                            selectedPhotos: $selectedPhotos,
                            onCameraPhoto: importCameraPhoto
                        ) {
                            EmptyPhotoAddCard()
                        }
                        .buttonStyle(.plain)
                        .frame(height: 140)
                    }
                    ForEach(Array(pendingPhotos.enumerated()), id: \.element.id) { index, photo in
                        PendingPhotoThumbnail(photo: photo, index: index) {
                            pendingPhotos.removeAll { $0.id == photo.id }
                            photoCount = pendingPhotos.count
                        }
                            .frame(height: 140)
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
            if let matchCandidate {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(
                        matchCandidate.createdByAnotherAgent
                            ? "A patient with this name is already registered."
                            : "A patient with this name is already in your records."
                    )
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Show details") {
                        isMatchDetailsPresented = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent.opacity(0.35))
                }
            }
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

    private var patientProfileFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patient details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Optional")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }

            labeledField("Date of birth", required: false) {
                TextField("DD/MM/YYYY", text: $dateOfBirthText)
                    .keyboardType(.numbersAndPunctuation)
                    .textContentType(.birthdate)
                    .textFieldStyle(.roundedBorder)
                if !dateOfBirthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDateOfBirthValid {
                    Text("Enter the date as DD/MM/YYYY.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            labeledField("Age", required: false) {
                TextField("Age if date of birth is unknown", text: $patientAge)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedAge != nil)
                    .opacity(selectedAge == nil ? 1 : 0.72)
                    .onChange(of: dateOfBirthText) { _, _ in
                        if let selectedAge { patientAge = String(selectedAge) }
                    }
                if selectedAge != nil {
                    Text("Calculated automatically from the date of birth.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.brand)
                } else if !patientAge.isEmpty && !isPatientAgeValid {
                    Text("Enter an age between 0 and 130.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            labeledField("Gender", required: false) {
                Picker("Gender", selection: $gender) {
                    Text("Not specified").tag("")
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                    Text("Non-binary").tag("non_binary")
                    Text("Other").tag("other")
                    Text("Prefer not to say").tag("prefer_not_to_say")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            labeledField("Phone", required: false) {
                TextField("Patient phone number", text: $patientPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("Email", required: false) {
                TextField("Patient email address", text: $patientEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("Address or city / region", required: false) {
                TextField("Address, city or region", text: $patientAddress, axis: .vertical)
                    .lineLimit(2...4)
                    .textContentType(.fullStreetAddress)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("Occupation", required: false) {
                TextField("Patient occupation", text: $occupation)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("Short patient information", required: false) {
                TextField("Relevant personal context", text: $profileNote, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var compactPatientProfile: some View {
        if let patient = editCase?.patient {
            VStack(alignment: .leading, spacing: 7) {
                Text("PATIENT DETAILS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                if let dateOfBirth = patient.dateOfBirthDisplayName {
                    profileLine("Date of birth", patient.age.map { "\(dateOfBirth) · Age \($0)" } ?? dateOfBirth)
                } else if let age = patient.age { profileLine("Age", "\(age)") }
                if let gender = patient.genderDisplayName { profileLine("Gender", gender) }
                if let phone = patient.phone { profileLine("Phone", phone) }
                if let email = patient.email { profileLine("Email", email) }
                if let address = patient.address { profileLine("Address", address) }
                if let occupation = patient.occupation { profileLine("Occupation", occupation) }
                if let note = patient.profileNote { profileLine("Info", note) }
            }
        }
    }

    private func profileLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedAge: Int? {
        guard let date = Self.date(fromDisplay: dateOfBirthText) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    private var isDateOfBirthValid: Bool {
        dateOfBirthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || Self.date(fromDisplay: dateOfBirthText) != nil
    }

    private var isPatientAgeValid: Bool {
        patientAge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || Int(patientAge).map { (0...130).contains($0) } == true
    }

    private var patientProfileIsValid: Bool {
        isDateOfBirthValid && isPatientAgeValid
    }

    private var patientProfileInput: PatientProfileInput {
        PatientProfileInput(
            dateOfBirth: Self.apiDate(fromDisplay: dateOfBirthText),
            age: selectedAge == nil ? Int(patientAge) : nil,
            gender: Self.trimmedOrNil(gender),
            phone: Self.trimmedOrNil(patientPhone),
            email: Self.trimmedOrNil(patientEmail),
            address: Self.trimmedOrNil(patientAddress),
            occupation: Self.trimmedOrNil(occupation),
            profileNote: Self.trimmedOrNil(profileNote)
        )
    }

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func apiDate(fromDisplay value: String) -> String? {
        guard let date = date(fromDisplay: value) else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func displayDate(fromAPI value: String?) -> String {
        guard let value else { return "" }
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return value }
        return String(format: "%02d/%02d/%04d", components[2], components[1], components[0])
    }

    private static func date(fromDisplay value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(whereSeparator: { "/-.".contains($0) }).compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(
            year: components[2], month: components[1], day: components[0]
        )), date <= .now else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == components[2], verified.month == components[1], verified.day == components[0] else {
            return nil
        }
        return date
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
        VStack(spacing: 0) {
            caseStatusBand

            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text(patientName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if canEditCase {
                        Button(detailsExpanded ? "Done" : "Edit", systemImage: detailsExpanded ? "checkmark" : "pencil") {
                            withAnimation(.easeInOut(duration: 0.2)) { detailsExpanded.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                if let editCase, !canEditCase {
                    Label("Added by \(editCase.agentName)", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Text(agentNote)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    summaryMetric("Estimated grafts", grafts)
                    summaryMetric("Estimated price", AppCurrency.amount(price))
                }

                if detailsExpanded {
                    Divider()
                    VStack(spacing: 12) {
                        labeledField("Patient name", required: true) {
                            TextField("Patient name", text: $patientName)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 10) {
                            labeledField("Estimated grafts", required: true) {
                                TextField("3,200", text: $grafts)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("Estimated price", required: true) {
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
                        patientProfileFields
                    }
                } else if editCase?.patient.hasProfileDetails == true {
                    Divider()
                    compactPatientProfile
                }
            }
            .padding(14)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private var caseStatusBand: some View {
        HStack(spacing: 8) {
            Image(systemName: caseStatusIcon)
            Text(editCase?.status.title ?? statusText)
                .fontWeight(.bold)
            Spacer(minLength: 8)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(caseStatusColor)
        .accessibilityElement(children: .combine)
    }

    private var caseStatusIcon: String {
        switch editCase?.status {
        case .waiting: "clock.fill"
        case .answered: "exclamationmark.circle.fill"
        case .closed: "checkmark.circle.fill"
        case nil: "circle.fill"
        }
    }

    private var caseStatusColor: Color {
        switch editCase?.status {
        case .waiting: AppTheme.accent
        case .answered: Color(red: 0.78, green: 0.16, blue: 0.14)
        case .closed: Color(red: 0.08, green: 0.52, blue: 0.32)
        case nil: AppTheme.brand
        }
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

            if photoCount > 0, canEditCase {
                PhotoSourceButton(
                    selectedPhotos: $selectedPhotos,
                    onCameraPhoto: importCameraPhoto
                ) {
                    Label("Add photos", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if isImportingPhotos {
                ProgressView("Uploading photos…")
                    .font(.caption)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 14
            ) {
                if photoCount == 0 {
                    if canEditCase {
                        PhotoSourceButton(
                            selectedPhotos: $selectedPhotos,
                            onCameraPhoto: importCameraPhoto
                        ) {
                            EmptyPhotoAddCard()
                        }
                        .buttonStyle(.plain)
                        .frame(height: 108)
                    } else {
                        NoPhotosView()
                            .frame(maxWidth: .infinity, minHeight: 108)
                    }
                }
                ForEach(0..<photoCount, id: \.self) { index in
                    let photoID = editCase?.photoIDs.indices.contains(index) == true ? editCase?.photoIDs[index] : nil
                    CasePhotoView(
                        photoID: photoID,
                        index: index,
                        reloadToken: photoReloadToken,
                        onDelete: canEditCase ? photoDeleteAction(for: photoID) : nil,
                        onTap: photoPreviewAction(for: photoID)
                    )
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                                .padding(6)
                        }
                }
            }

        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    @ViewBuilder
    private var conversationSection: some View {
        if let editCase {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONVERSATION")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 4)

                ForEach(editCase.messages) { message in
                    ConversationMessageBubble(
                        message: message,
                        canDelete: message.role == .agent && message.authorID == state.currentUser?.id,
                        onDelete: { pendingMessageDeletion = message }
                    )
                }

                if canEditCase {
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.top, 4)
                }
            }
        }
    }

    private func finalPlanSection(_ item: ConsultationCase) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Final agreed plan")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if item.status == .closed {
                    Label("Confirmed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.brandDark)
                } else {
                    Text("Required")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentInk)
                }
            }

            if let recommendation = latestDoctorRecommendation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Doctor recommendation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    HStack(spacing: 10) {
                        summaryMetric("Recommended grafts", recommendation.approximateGrafts ?? "—")
                        summaryMetric(
                            "Recommended price",
                            recommendation.recommendedPrice.map(AppCurrency.amount) ?? "—"
                        )
                    }
                }
            }

            if item.status == .closed {
                HStack(spacing: 10) {
                    summaryMetric("Final grafts", item.finalGrafts ?? item.agentGrafts)
                    summaryMetric("Final price", AppCurrency.amount(item.finalPrice ?? item.agentPrice))
                }
            } else if canEditCase {
                Text("Using the doctor’s recommendation, enter the graft number and price agreed with the patient.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

                HStack(spacing: 10) {
                    labeledField("Final agreed grafts", required: true) {
                        TextField("e.g. 2,600", text: $finalGrafts)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Final agreed price", required: true) {
                        HStack(spacing: 6) {
                            Text(AppCurrency.symbol)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            TextField("e.g. 2,700", text: $finalPrice)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            } else {
                Label("\(item.agentName) will confirm the final agreed plan.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
    }

    private func photoDeleteAction(for photoID: String?) -> (() -> Void)? {
        guard canEditCase, let photoID else { return nil }
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
                allowsEditing: canEditCase
            )
        } catch {
            state.errorMessage = "The photo could not be opened."
        }
    }

    @MainActor
    private func sendAnnotatedPhoto(
        _ data: Data, contentType: String, note: String, caseID: UUID
    ) async -> Bool {
        guard canEditCase else { return false }
        statusText = "Sending annotated photo…"
        if await state.sendPhotoMessage(
            caseID: caseID, data: data, contentType: contentType, text: note
        ) {
            statusText = "Waiting for Doctor · Annotated photo sent"
            returnedToDoctor = true
            return true
        } else {
            statusText = "Annotated photo could not be sent"
            return false
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
        if canEditCase {
            if isEditMode {
                if detailsExpanded || (editCase?.status == .answered && latestDoctorRecommendation != nil && !returnedToDoctor) {
                    editActionBar
                }
            } else {
                wizardActionBar
            }
        }
    }

    private var editActionBar: some View {
        Group {
            if detailsExpanded {
                Button("Save changes") {
                    if let editCase {
                        Task {
                            if await state.saveAgentValues(
                                caseID: editCase.id, patientName: patientName, patientProfile: patientProfileInput,
                                grafts: grafts, currency: currency, price: price
                            ) {
                                statusText = "Changes saved"
                                detailsExpanded = false
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .disabled(!patientProfileIsValid)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if editCase?.status == .answered && latestDoctorRecommendation != nil && !returnedToDoctor {
                Button("Save Final Plan & Close") {
                    if let editCase {
                        Task {
                            if await state.confirmAndClose(
                                caseID: editCase.id,
                                finalGrafts: finalGrafts,
                                finalPrice: finalPrice
                            ) {
                                statusText = "Final plan confirmed · Closed"
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .disabled(!finalPlanReady)
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
            return patientProfileIsValid
                && (patientVerification == .newPatient || patientVerification == .differentConfirmed)
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
                patientProfile: patientProfileInput,
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
            dateOfBirthText = Self.displayDate(fromAPI: item.patient.dateOfBirth)
            patientAge = item.patient.age.map(String.init) ?? ""
            gender = item.patient.gender ?? ""
            patientPhone = item.patient.phone ?? ""
            patientEmail = item.patient.email ?? ""
            patientAddress = item.patient.address ?? ""
            occupation = item.patient.occupation ?? ""
            profileNote = item.patient.profileNote ?? ""
            grafts = item.agentGrafts
            currency = AppCurrency.code
            price = item.agentPrice
            finalGrafts = item.finalGrafts
                ?? latestDoctorRecommendation?.approximateGrafts
                ?? ""
            finalPrice = item.finalPrice
                ?? latestDoctorRecommendation?.recommendedPrice.map { recommended in
                    String(AppCurrency.amount(recommended).dropFirst())
                }
                ?? ""
            agentNote = item.agentNote
            photoCount = item.photoCount
            statusText = item.status.title
        } else {
            detailsExpanded = true
            patientName = ""
            dateOfBirthText = ""
            patientAge = ""
            gender = ""
            patientPhone = ""
            patientEmail = ""
            patientAddress = ""
            occupation = ""
            profileNote = ""
            grafts = "3,200"
            currency = AppCurrency.code
            price = "2,850"
            finalGrafts = ""
            finalPrice = ""
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

    private func importCameraPhoto(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            state.errorMessage = "The captured photo could not be read."
            return
        }
        Task { await acceptImportedPhotos([CasePhotoUpload(data: jpeg, contentType: "image/jpeg")]) }
    }

    @MainActor
    private func acceptImportedPhotos(_ imported: [CasePhotoUpload]) async {
        guard !imported.isEmpty, !isImportingPhotos else { return }
        isImportingPhotos = true
        defer { isImportingPhotos = false }

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

    @MainActor
    private func verifyPatientNameAfterEditing() async {
        let query = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.split(whereSeparator: \.isWhitespace).count >= 2 else {
            matchCandidate = nil
            patientVerification = .idle
            return
        }

        duplicateResolution = nil
        matchCandidate = nil
        patientVerification = .checking
        await checkForExistingPatient(named: query)
    }

    @MainActor
    private func checkForExistingPatient(named query: String) async {
        guard duplicateResolution == nil else { return }
        do {
            let first = try await state.patientMatcher.findMatches(for: query).first
            guard patientName.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            if let first {
                patientVerification = .matchFound
                matchCandidate = first
            } else {
                patientVerification = .newPatient
                statusText = "New patient · Name verified"
            }
        } catch {
            guard patientName.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
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
            dateOfBirthText = Self.displayDate(fromAPI: item.patient.dateOfBirth)
            patientAge = item.patient.age.map(String.init) ?? ""
            gender = item.patient.gender ?? ""
            patientPhone = item.patient.phone ?? ""
            patientEmail = item.patient.email ?? ""
            patientAddress = item.patient.address ?? ""
            occupation = item.patient.occupation ?? ""
            profileNote = item.patient.profileNote ?? ""
            grafts = item.agentGrafts
            currency = AppCurrency.code
            price = item.agentPrice
            finalGrafts = item.finalGrafts
                ?? item.messages.last(where: {
                    $0.role == .doctor
                        && ($0.approximateGrafts != nil || $0.recommendedPrice != nil)
                })?.approximateGrafts
                ?? ""
            finalPrice = item.finalPrice
                ?? item.messages.last(where: {
                    $0.role == .doctor
                        && ($0.approximateGrafts != nil || $0.recommendedPrice != nil)
                })?.recommendedPrice.map { recommended in
                    String(AppCurrency.amount(recommended).dropFirst())
                }
                ?? ""
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

private struct EmptyPhotoAddCard: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.brand)
            Text("Add photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.brandDark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.brand.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Add a patient photo")
    }
}

private struct PhotoSourceButton<Label: View>: View {
    @Binding var selectedPhotos: [PhotosPickerItem]
    let onCameraPhoto: (UIImage) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showsSourceOptions = false
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false

    var body: some View {
        Button { showsSourceOptions = true } label: { label() }
            .confirmationDialog("Add photos", isPresented: $showsSourceOptions, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") { showsCamera = true }
                }
                Button("Choose from Photo Library", systemImage: "photo.on.rectangle") {
                    showsPhotoLibrary = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $selectedPhotos,
                maxSelectionCount: 12,
                matching: .images
            )
            .fullScreenCover(isPresented: $showsCamera) {
                CameraImagePicker(
                    onImagePicked: { image in
                        showsCamera = false
                        onCameraPhoto(image)
                    },
                    onCancel: { showsCamera = false }
                )
                .ignoresSafeArea()
            }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onImagePicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private enum PhotoImportError: Error {
    case unreadable
}

private struct PendingPhotoThumbnail: View {
    let photo: CasePhotoUpload
    let index: Int
    let onRemove: () -> Void

    var body: some View {
        Group {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PhotoUnavailableView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.red, in: Circle())
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .padding(8)
            .accessibilityLabel("Remove selected photo \(index + 1)")
        }
        .accessibilityLabel("Selected patient photo \(index + 1)")
    }
}
