import SwiftUI

struct DoctorQueueView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: DoctorQueueFilter = .waiting
    @State private var searchText = ""
    @State private var oldestFirst = true
    @State private var selectedCase: ConsultationCase?

    private var filteredCases: [ConsultationCase] {
        state.cases
            .filter(matchesQueue)
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [item.patient.name, item.reference, item.agencyName, item.agentName, item.agentNote]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { oldestFirst ? $0.uploadedAt < $1.uploadedAt : $0.uploadedAt > $1.uploadedAt }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 12) {
                            queueControls
                                .padding(.horizontal, 12)
                            caseGrid(minimumEmptyHeight: max(320, proxy.size.height - 170))
                        }
                    } header: {
                        searchHeader
                    }
                }
                .padding(.bottom, 20)
            }
            .refreshable { await state.load() }
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCase) { item in
            CaseDetailView(caseID: item.id)
                .environmentObject(state)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Search patients, agencies or notes", text: $searchText)
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

    private var queueControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                ForEach(DoctorQueueFilter.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            filter = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(filterTitle(item))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("\(count(for: item))")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    (filter == item ? AppTheme.surfaceStrong : AppTheme.inset),
                                    in: Capsule()
                                )
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == item ? AppTheme.accentInk : AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(filter == item ? AppTheme.accent : AppTheme.surfaceStrong, in: Capsule())
                        .overlay(Capsule().stroke(filter == item ? AppTheme.accent : AppTheme.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filterTitle(item)), \(count(for: item)) cases")
                }
            }

            HStack {
                Text("\(filteredCases.count) \(filteredCases.count == 1 ? "patient" : "patients")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button {
                    oldestFirst.toggle()
                } label: {
                    Label(oldestFirst ? "Oldest first" : "Newest first", systemImage: oldestFirst ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func caseGrid(minimumEmptyHeight: CGFloat) -> some View {
        if filteredCases.isEmpty {
            ContentUnavailableView("No patients", systemImage: "tray", description: Text("No patients match this view."))
                .frame(maxWidth: .infinity, minHeight: minimumEmptyHeight)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredCases) { item in
                    DoctorWorkCard(item: item) { selectedCase = item }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func filterTitle(_ item: DoctorQueueFilter) -> String {
        switch item {
        case .waiting: "Needs review"
        case .answered: "Sent"
        case .confirmed: "Confirmed"
        }
    }

    private func matchesQueue(_ item: ConsultationCase) -> Bool {
        switch filter {
        case .waiting: item.status == .waiting
        case .answered: item.status == .answered
        case .confirmed: item.status == .closed
        }
    }

    private func count(for filter: DoctorQueueFilter) -> Int {
        state.cases.filter { item in
            switch filter {
            case .waiting: item.status == .waiting
            case .answered: item.status == .answered
            case .confirmed: item.status == .closed
            }
        }.count
    }
}

private struct DoctorWorkCard: View {
    let item: ConsultationCase
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 8)
                    Label(waitingTime, systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOverdue ? statusColor : AppTheme.muted)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.patient.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !patientSummary.isEmpty {
                        Text(patientSummary)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Text(item.agentNote)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    infoPill(icon: "leaf", text: "Est. \(item.agentGrafts) grafts")
                    infoPill(icon: "photo.on.rectangle", text: "\(item.photoCount) photos")
                    infoPill(icon: "bubble.left", text: "\(messageCount)")
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                    Text(item.agencyName ?? "No agency")
                        .lineLimit(1)
                    Text("·")
                    Text(item.agentName)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(statusColor)
                .frame(width: 5)
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border))
            .shadow(color: AppTheme.ink.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens patient details")
    }

    private var messageCount: Int {
        item.messages.filter { $0.role != .system }.count
    }

    private var patientSummary: String {
        [item.patient.age.map { "\($0) years" }, item.patient.genderDisplayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var isOverdue: Bool {
        item.status == .waiting && Date().timeIntervalSince(item.uploadedAt) >= 86_400
    }

    private var statusTitle: String {
        switch item.status {
        case .waiting: isOverdue ? "Needs review · overdue" : "Needs review"
        case .answered: "Sent · waiting for agent"
        case .closed: "Confirmed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .waiting:
            isOverdue ? Color(red: 0.78, green: 0.16, blue: 0.14) : AppTheme.accent
        case .answered:
            AppTheme.brand
        case .closed:
            AppTheme.muted
        }
    }

    private var waitingTime: String {
        let seconds = max(0, Date().timeIntervalSince(item.uploadedAt))
        if seconds < 3_600 {
            return "\(max(1, Int((seconds / 60).rounded()))) min"
        }
        if seconds < 86_400 {
            return "\(max(1, Int((seconds / 3_600).rounded()))) hr"
        }
        return "\(max(1, Int((seconds / 86_400).rounded()))) days"
    }

    private func infoPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.inset, in: Capsule())
    }
}

struct StatusChip: View {
    let status: ConsultationStatus

    var body: some View {
        Label(title, systemImage: "circle.fill")
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch status {
        case .waiting: "Needs review"
        case .answered: "Sent · Waiting for agent"
        case .closed: "Confirmed"
        }
    }

    private var color: Color {
        switch status {
        case .waiting: AppTheme.accent
        case .answered: AppTheme.brand
        case .closed: AppTheme.muted
        }
    }
}
