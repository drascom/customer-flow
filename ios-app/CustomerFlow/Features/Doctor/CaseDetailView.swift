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
    private var responseStarted: Bool {
        !grafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var responseReady: Bool {
        !grafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item {
                    VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.patient.name).font(.title2.bold())
                                    Text("\(item.reference) · Uploaded by \(item.agentName)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                StatusChip(status: item.status)
                            }

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
                            .tabViewStyle(.page)
                            .frame(height: 330)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                            Button("Open & Mark Up", systemImage: "pencil.and.outline") {
                                guard item.photoIDs.indices.contains(photoIndex) else { return }
                                Task { await openNativePreview(photoID: item.photoIDs[photoIndex], caseID: item.id) }
                            }
                            .buttonStyle(.bordered)

                            detailSection("Agent note") {
                                Text(item.agentNote).foregroundStyle(AppTheme.ink)
                            }

                            HStack(spacing: 10) {
                                detailMetric("Estimated grafts", item.agentGrafts)
                                detailMetric("Estimated price", AppCurrency.amount(item.agentPrice))
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

                            detailSection("Case conversation") {
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

                        if item.status == .waiting {
                            responseComposer(item)
                        } else {
                            detailSection("Current state") {
                                Text(item.status == .answered ? "Your response has been sent. The agent must confirm before this case closes." : "The agent confirmed and closed this case.")
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Case Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Doctor response").font(.headline)
            HStack {
                TextField("Approx. grafts", text: $grafts)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text(AppCurrency.symbol)
                        .font(.headline)
                    TextField("Recommended price", text: $price)
                        .keyboardType(.decimalPad)
                }
                .padding(.horizontal, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border))
            }
            TextField("Clinical assessment and recommendation", text: $response, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)

            if item.assignedDoctorID == nil {
                Label("Sending this response assigns the patient to you.", systemImage: "person.badge.plus")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
            if responseStarted && !responseReady {
                Label("Complete all three fields to send the recommendation.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }

            if isSending {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if responseReady {
                Button(item.assignedDoctorID == nil ? "Respond & Take Patient" : "Send Response") {
                    Task {
                        isSending = true
                        let sent = await state.sendRecommendation(
                            caseID: item.id,
                            recommendation: DoctorRecommendation(approximateGrafts: grafts, recommendedPrice: AppCurrency.amount(price), text: response)
                        )
                        isSending = false
                        if sent { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
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
                    Text(message.createdAt, style: .relative).font(.caption2).foregroundStyle(AppTheme.muted)
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
