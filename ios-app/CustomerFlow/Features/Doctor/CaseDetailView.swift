import SwiftUI

struct CaseDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let caseID: UUID

    @State private var photoIndex = 0
    @State private var grafts = ""
    @State private var price = ""
    @State private var response = ""
    @State private var isSending = false
    @State private var photoPreview: NativePhotoPreviewRequest?
    @State private var pendingMessageDeletion: ConsultationMessage?

    private var item: ConsultationCase? { state.cases.first { $0.id == caseID } }
    private var responseReady: Bool {
        !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item {
                    VStack(alignment: .leading, spacing: 16) {
                        caseHeader(item)
                        photoGallery(item)

                        detailSection("Patient need") {
                            Text(item.agentNote)
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                        }

                        agentEstimate(item)

                        if item.patient.hasProfileDetails {
                            patientDetails(item.patient)
                        }

                        if let finalGrafts = item.finalGrafts,
                           let finalPrice = item.finalPrice {
                            detailSection("Final agreed plan") {
                                HStack(spacing: 10) {
                                    detailMetric("Final grafts", finalGrafts)
                                    detailMetric("Final price", AppCurrency.amount(finalPrice))
                                }
                            }
                        }

                        detailSection("Conversation") {
                            VStack(spacing: 10) {
                                ForEach(item.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        canDelete: message.role == .doctor && message.authorID == state.currentUser?.id,
                                        onDelete: { pendingMessageDeletion = message }
                                    )
                                }
                            }
                        }

                        if item.status != .closed {
                            Text("Reply below to send your assessment to the agent.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 4)
                        } else {
                            detailSection("Current state") {
                                Text("The agent confirmed and closed this case.")
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Patient review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.surfaceStrong, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let item, item.status != .closed {
                    responseComposer(item)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Rectangle().fill(AppTheme.border).frame(height: 1)
                        }
                }
            }
            .fullScreenCover(item: $photoPreview) { request in
                NativePhotoPreview(request: request) { data, contentType in
                    Task { await state.sendPhotoMessage(caseID: request.caseID, data: data, contentType: contentType) }
                } onClose: {
                    photoPreview = nil
                }
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
                    guard let message = pendingMessageDeletion else { return }
                    pendingMessageDeletion = nil
                    Task { _ = await state.deleteMessage(caseID: caseID, messageID: message.id) }
                }
                Button("Cancel", role: .cancel) { pendingMessageDeletion = nil }
            } message: {
                Text("The comment will disappear from the conversation, but administrators will retain the record.")
            }
        }
    }

    private func caseHeader(_ item: ConsultationCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.patient.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                StatusChip(status: item.status)
            }

            Divider()
                .overlay(AppTheme.muted.opacity(0.22))

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(item.uploadedAt.compactRelativeText)
                Spacer(minLength: 12)
                Image(systemName: "building.2")
                Text("\(item.agencyName ?? "No agency") · \(item.agentName)")
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func photoGallery(_ item: ConsultationCase) -> some View {
        if item.photoCount == 0 {
            NoPhotosView()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            VStack(alignment: .leading, spacing: 9) {
                TabView(selection: $photoIndex) {
                    ForEach(0..<item.photoCount, id: \.self) { index in
                        CasePhotoView(
                            photoID: item.photoIDs.indices.contains(index) ? item.photoIDs[index] : nil,
                            index: index,
                            onTap: item.photoIDs.indices.contains(index) ? {
                                Task { await openNativePreview(photoID: item.photoIDs[index], caseID: item.id) }
                            } : nil
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(photoIndex + 1) / \(item.photoCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(12)
                }

                HStack {
                    Label("Swipe to review all photos", systemImage: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    Button("Enlarge & Mark Up", systemImage: "pencil.and.outline") {
                        guard item.photoIDs.indices.contains(photoIndex) else { return }
                        Task { await openNativePreview(photoID: item.photoIDs[photoIndex], caseID: item.id) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
            }
        }
    }

    private func agentEstimate(_ item: ConsultationCase) -> some View {
        detailSection("Agent estimate") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    detailMetric("Estimated grafts", item.agentGrafts)
                    detailMetric("Estimated price", AppCurrency.amount(item.agentPrice))
                }
                Text("Use this as context; your clinical recommendation can be different.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    @MainActor
    private func openNativePreview(photoID: String, caseID: UUID) async {
        do {
            guard let item else { return }
            let photoIDs = item.photoIDs
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

    @ViewBuilder
    private func responseComposer(_ item: ConsultationCase) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Reply to agent")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 8) {
                TextField("Grafts (optional)", text: $grafts)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 6) {
                    Text(AppCurrency.symbol)
                        .font(.caption.bold())
                    TextField("Price (optional)", text: $price)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write your assessment or question", text: $response, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.border))

                if isSending {
                    ProgressView()
                        .frame(width: 42, height: 42)
                } else {
                    Button {
                        Task { await sendResponse(for: item) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!responseReady)
                    .opacity(responseReady ? 1 : 0.45)
                    .accessibilityLabel(item.assignedDoctorID == nil ? "Send and take patient" : "Send message")
                }
            }

            if item.assignedDoctorID == nil {
                Label("Sending your first message assigns the patient to you.", systemImage: "person.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 12, y: -2)
    }

    @MainActor
    private func sendResponse(for item: ConsultationCase) async {
        isSending = true
        let trimmedGrafts = grafts.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = price.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent = await state.sendRecommendation(
            caseID: item.id,
            recommendation: DoctorRecommendation(
                approximateGrafts: trimmedGrafts.isEmpty ? nil : trimmedGrafts,
                recommendedPrice: trimmedPrice.isEmpty ? nil : AppCurrency.amount(trimmedPrice),
                text: response.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        isSending = false
        if sent {
            grafts = ""
            price = ""
            response = ""
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(AppTheme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border))
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(AppTheme.muted)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border))
    }

    private func patientDetails(_ patient: Patient) -> some View {
        detailSection("Patient details") {
            VStack(alignment: .leading, spacing: 9) {
                if let dateOfBirth = patient.dateOfBirthDisplayName {
                    patientDetailLine("Date of birth", patient.age.map { "\(dateOfBirth) · Age \($0)" } ?? dateOfBirth)
                } else if let age = patient.age { patientDetailLine("Age", "\(age)") }
                if let gender = patient.genderDisplayName { patientDetailLine("Gender", gender) }
                if let phone = patient.phone { patientDetailLine("Phone", phone) }
                if let email = patient.email { patientDetailLine("Email", email) }
                if let address = patient.address { patientDetailLine("Address", address) }
                if let occupation = patient.occupation { patientDetailLine("Occupation", occupation) }
                if let note = patient.profileNote { patientDetailLine("Info", note) }
            }
        }
    }

    private func patientDetailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MessageBubble: View {
    let message: ConsultationMessage
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(authorBadge)
                .font(.caption2.bold())
                .frame(width: 32, height: 32)
                .background((message.role == .doctor ? AppTheme.brand : AppTheme.accent).opacity(0.14), in: Circle())
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
                    Text(message.createdAt.compactRelativeText).font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Text(message.text).font(.body)
                if let attachmentPhotoID = message.attachmentPhotoID {
                    MessagePhotoView(messageID: attachmentPhotoID)
                }
                if let grafts = message.approximateGrafts, let price = message.recommendedPrice {
                    HStack {
                        Text("Approx. \(grafts) grafts")
                        Text("Recommended \(AppCurrency.amount(price))")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.brand)
                }
            }
            .padding(11)
            .background((message.role == .doctor ? AppTheme.brand : AppTheme.accent).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var authorBadge: String {
        switch message.role {
        case .doctor: "DR"
        case .agent: "AG"
        case .admin: "AD"
        case .system: "SY"
        }
    }
}
