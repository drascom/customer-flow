import SwiftUI

struct AdminCaseCard: View {
    @EnvironmentObject private var state: AppState

    let item: AdminCase
    let doctors: [AdminUser]
    let isReadOnly: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAssign: (String?) -> Void
    let onPurgePhoto: (String) -> Void

    @State private var photoPreview: NativePhotoPreviewRequest?
    @State private var pendingPurgePhotoID: String?
    @State private var showsConversation = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.patientName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        statusChip
                    }

                    HStack(spacing: 6) {
                        Text(item.reference)
                        Text("•")
                        Text(item.uploadedAt, style: .relative)
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.muted)

                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                        Text(item.agencyName ?? "No agency")
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(item.agentName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)

                    if let author = item.latestMessageAuthor,
                       let text = item.latestMessageText,
                       let createdAt = item.latestMessageAt {
                        Divider().padding(.vertical, 2)
                        LatestMessagePreview(
                            author: author,
                            text: text,
                            createdAt: createdAt,
                            hasPhoto: item.latestMessageHasPhoto ?? false
                        )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.vertical, 12)

                HStack(spacing: 8) {
                    metric(title: "Grafts", value: item.grafts)
                    metric(title: "Price", value: AppCurrency.amount(item.price))
                    metric(title: "Media", value: "\(item.photoCount) · \(item.messageCount)")
                }

                if !item.photos.isEmpty {
                    adminPhotos
                        .padding(.top, 12)
                }

                conversationButton
                    .padding(.top, 10)

                Group {
                    if isReadOnly {
                        assignmentLabel
                    } else {
                        Menu {
                            Button("Unassigned") { onAssign(nil) }
                            Divider()
                            ForEach(doctors) { doctor in
                                Button {
                                    onAssign(doctor.id)
                                } label: {
                                    if doctor.id == item.doctorID {
                                        Label(doctor.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(doctor.displayName)
                                    }
                                }
                            }
                        } label: {
                            assignmentLabel
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .fullScreenCover(item: $photoPreview) { request in
            NativePhotoPreview(request: request) { _, _ in } onClose: {
                photoPreview = nil
            }
        }
        .sheet(isPresented: $showsConversation) {
            AdminConversationSheet(item: item)
                .presentationDetents([.fraction(0.92)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationContentInteraction(.scrolls)
        }
        .confirmationDialog(
            "Permanently delete this photo?",
            isPresented: Binding(
                get: { pendingPurgePhotoID != nil },
                set: { if !$0 { pendingPurgePhotoID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                guard let photoID = pendingPurgePhotoID else { return }
                pendingPurgePhotoID = nil
                onPurgePhoto(photoID)
            }
            Button("Cancel", role: .cancel) { pendingPurgePhotoID = nil }
        } message: {
            Text("This removes the retained file from the server and cannot be undone.")
        }
    }

    private var assignmentLabel: some View {
                    HStack(spacing: 8) {
                        Image(systemName: "stethoscope")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Assigned doctor")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Text(item.doctorName ?? "Unassigned")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                        Spacer()
                        if !isReadOnly {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(AppTheme.brand)
                        }
                    }
                    .padding(11)
                    .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var conversationButton: some View {
        Button {
            showsConversation = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(AppTheme.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("View conversation")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(item.messages.count) messages")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if item.deletedMessageCount > 0 {
                    Text("\(item.deletedMessageCount) deleted")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(11)
            .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var adminPhotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if item.deletedPhotoCount > 0 {
                    Text("\(item.deletedPhotoCount) deleted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(Array(item.photos.enumerated()), id: \.element.id) { index, photo in
                    CasePhotoView(
                        photoID: photo.available ? photo.id : nil,
                        index: index,
                        onTap: photo.available ? { Task { await openNativePreview(photoID: photo.id) } } : nil
                    )
                        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                .padding(5)
                        }
                        .overlay {
                            if photo.deleted {
                                ZStack {
                                    Color.black.opacity(0.58)
                                    VStack(spacing: 3) {
                                        Image(systemName: "trash.fill")
                                        Text("Deleted by agent")
                                            .multilineTextAlignment(.center)
                                        if let name = photo.deletedByName {
                                            Text(name).lineLimit(1)
                                        }
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(6)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if photo.deleted && !isReadOnly {
                                Button {
                                    pendingPurgePhotoID = photo.id
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(.red, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                                .accessibilityLabel("Delete photo permanently")
                            }
                        }
                }
            }
        }
    }

    @MainActor
    private func openNativePreview(photoID: String) async {
        guard let caseID = UUID(uuidString: item.id) else { return }
        let photoIDs = item.photos.filter(\.available).map(\.id)
        do {
            var photoData: [String: Data] = [:]
            for itemID in photoIDs {
                photoData[itemID] = try await state.photoData(photoID: itemID)
            }
            photoPreview = try NativePhotoPreviewRequest.make(
                caseID: caseID,
                photoIDs: photoIDs,
                photoData: photoData,
                initialIndex: photoIDs.firstIndex(of: photoID) ?? 0,
                allowsEditing: false
            )
        } catch {
            state.errorMessage = "The photo could not be opened."
        }
    }

    private var statusChip: some View {
        Text(shortStatus)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.13), in: Capsule())
    }

    private var shortStatus: String {
        switch item.status {
        case .waiting: "Waiting"
        case .answered: "Answered"
        case .closed: "Closed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .waiting: AppTheme.accent
        case .answered: AppTheme.brand
        case .closed: AppTheme.muted
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AdminConversationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: AdminCase

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.patientName)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text("\(item.reference) · Conversation")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.inset, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close conversation")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if item.messages.isEmpty {
                        ContentUnavailableView(
                            "No conversation yet",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(item.messages) { message in
                            messageRow(message)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(AppTheme.background)
    }

    private func messageRow(_ message: AdminCaseMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(message.author)
                    .font(.caption.bold())
                Text(message.role.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text(message.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }

            Text(message.text)
                .font(.body)

            if let attachmentPhotoID = message.attachmentPhotoID {
                MessagePhotoView(messageID: attachmentPhotoID)
            }

            if let grafts = message.approximateGrafts,
               let price = message.recommendedPrice {
                HStack(spacing: 10) {
                    Text("Approx. \(grafts) grafts")
                    Text("Recommended \(AppCurrency.amount(price))")
                }
                .font(.caption.bold())
                .foregroundStyle(AppTheme.brand)
            }

            if message.deletedAt != nil {
                Label(
                    "Deleted by \(message.deletedByName ?? message.author)",
                    systemImage: "trash"
                )
                .font(.caption2.bold())
                .foregroundStyle(.red)
            }
        }
        .foregroundStyle(message.deletedAt == nil ? AppTheme.ink : AppTheme.muted)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(message.deletedAt == nil ? AppTheme.border : .red.opacity(0.35))
        }
    }
}
