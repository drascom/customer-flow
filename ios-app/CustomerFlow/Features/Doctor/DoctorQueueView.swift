import SwiftUI

struct DoctorQueueView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var filter: DoctorQueueFilter = .all
    @State private var selectedAgencyName: String?
    @State private var searchText = ""
    @State private var oldestFirst = true
    @State private var selectedCase: ConsultationCase?
    @FocusState private var isSearchFocused: Bool

    private var usesWideLayout: Bool { horizontalSizeClass == .regular }

    private var filteredCases: [ConsultationCase] {
        state.cases
            .filter(matchesQueue)
            .filter { item in
                guard let selectedAgencyName else { return true }
                return item.agencyName == selectedAgencyName
            }
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

    private var agencyOptions: [String] {
        Array(Set(state.cases.compactMap { item in
            let name = item.agencyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name : nil
        }))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        Group {
            if usesWideLayout {
                wideWorkspace
            } else {
                compactWorkspace
            }
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: state.pendingNotificationCaseID) { _, caseID in
            guard let caseID, let item = state.cases.first(where: { $0.id == caseID }) else { return }
            selectedCase = item
            state.consumePendingNotificationCase()
        }
        .onChange(of: filter) { _, _ in reconcileSelectedCase() }
        .onChange(of: selectedAgencyName) { _, _ in reconcileSelectedCase() }
        .onChange(of: searchText) { _, _ in reconcileSelectedCase() }
        .onChange(of: state.cases) { _, _ in reconcileSelectedCase() }
        .sheet(item: Binding(
            get: { usesWideLayout ? nil : selectedCase },
            set: { selectedCase = $0 }
        )) { item in
            CaseDetailView(caseID: item.id)
                .environmentObject(state)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isSearchFocused = false }
            }
        }
    }

    private func reconcileSelectedCase() {
        guard let selectedCase else { return }
        guard filteredCases.contains(where: { $0.id == selectedCase.id }) else {
            self.selectedCase = nil
            return
        }
        self.selectedCase = state.cases.first(where: { $0.id == selectedCase.id })
    }

    private var compactWorkspace: some View {
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
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await state.load() }
        }
    }

    private var wideWorkspace: some View {
        HStack(spacing: 0) {
            wideSidebar
                .frame(width: 220)
                .background(.ultraThinMaterial)

            Divider()

            VStack(spacing: 0) {
                searchHeader
                Divider().overlay(AppTheme.border)
                ScrollView {
                    caseGrid(minimumEmptyHeight: 420)
                        .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await state.load() }
            }
            .frame(minWidth: 340, idealWidth: 400, maxWidth: 470)

            Divider()

            Group {
                if let selectedCase {
                    CaseDetailView(caseID: selectedCase.id, showsCloseButton: false)
                        .environmentObject(state)
                        .id(selectedCase.id)
                } else {
                    ContentUnavailableView(
                        "Select a patient",
                        systemImage: "person.text.rectangle",
                        description: Text("Choose a case to review photos, details and conversation.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
        }
    }

    private var wideSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Patient review")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("\(filteredCases.count) visible cases")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            VStack(spacing: 7) {
                ForEach(DoctorQueueFilter.allCases) { item in
                    Button {
                        isSearchFocused = false
                        withAnimation(.easeInOut(duration: 0.18)) { filter = item }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: sidebarSymbol(for: item))
                                .frame(width: 20)
                            Text(filterTitle(item))
                            Spacer()
                            Text("\(count(for: item))")
                                .font(.caption.bold())
                                .foregroundStyle(filter == item ? AppTheme.accentInk : AppTheme.muted)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(filter == item ? AppTheme.accentInk : AppTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(filter == item ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 13))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("AGENCY")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.muted)
                wideAgencyFilter
            }

            Spacer()

            Button {
                oldestFirst.toggle()
            } label: {
                Label(oldestFirst ? "Oldest first" : "Newest first", systemImage: oldestFirst ? "arrow.up" : "arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private func sidebarSymbol(for item: DoctorQueueFilter) -> String {
        switch item {
        case .all: "tray.full"
        case .waiting: "clock"
        case .answered: "bubble.left.and.bubble.right"
        case .confirmed: "checkmark.seal"
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                TextField("Search patients, agencies or notes", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.done)
                    .onSubmit { isSearchFocused = false }
                if isSearchFocused || !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search and close keyboard")
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: 620, minHeight: 42)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))

            if !usesWideLayout {
                agencyFilterButton
            }
        }
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
                        isSearchFocused = false
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
                                .foregroundStyle(filter == item ? AppTheme.accentInk : AppTheme.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    (filter == item ? AppTheme.surfaceStrong : AppTheme.inset),
                                    in: Capsule()
                                )
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == item ? Color.white : AppTheme.muted)
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
                    .lineLimit(1)
                Spacer()
                Button {
                    isSearchFocused = false
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

    private var agencyFilterButton: some View {
        Menu {
            Button {
                selectedAgencyName = nil
            } label: {
                Label("All agencies", systemImage: selectedAgencyName == nil ? "checkmark" : "building.2")
            }
            if !agencyOptions.isEmpty {
                Divider()
                ForEach(agencyOptions, id: \.self) { agencyName in
                    Button {
                        selectedAgencyName = agencyName
                    } label: {
                        if selectedAgencyName == agencyName {
                            Label(agencyName, systemImage: "checkmark")
                        } else {
                            Text(agencyName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedAgencyName == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(selectedAgencyName == nil ? AppTheme.muted : AppTheme.brand)
                .frame(width: 42, height: 42)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedAgencyName.map { "Agency filter, \($0)" } ?? "Agency filter, all agencies")
    }

    private var wideAgencyFilter: some View {
        Menu {
            Button {
                selectedAgencyName = nil
            } label: {
                Label("All agencies", systemImage: selectedAgencyName == nil ? "checkmark" : "building.2")
            }
            if !agencyOptions.isEmpty {
                Divider()
                ForEach(agencyOptions, id: \.self) { agencyName in
                    Button {
                        selectedAgencyName = agencyName
                    } label: {
                        if selectedAgencyName == agencyName {
                            Label(agencyName, systemImage: "checkmark")
                        } else {
                            Text(agencyName)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                Text(selectedAgencyName ?? "All agencies")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.bold())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func caseGrid(minimumEmptyHeight: CGFloat) -> some View {
        if filteredCases.isEmpty {
            ContentUnavailableView("No patients", systemImage: "tray", description: Text("No patients match this view."))
                .frame(maxWidth: .infinity, minHeight: minimumEmptyHeight)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredCases) { item in
                    DoctorWorkCard(
                        item: item,
                        unreadNotificationCount: state.unreadNotificationCount(for: item.id),
                        isSelected: usesWideLayout && selectedCase?.id == item.id
                    ) {
                        isSearchFocused = false
                        selectedCase = item
                        Task { await state.markCaseNotificationsRead(item.id) }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func filterTitle(_ item: DoctorQueueFilter) -> String {
        switch item {
        case .all: "All Cases"
        case .waiting: "In Review"
        case .answered: "Answered"
        case .confirmed: "Confirmed"
        }
    }

    private func matchesQueue(_ item: ConsultationCase) -> Bool {
        switch filter {
        case .all: true
        case .waiting: item.status == .waiting && !item.isCompleted
        case .answered: item.status == .answered && !item.isCompleted
        case .confirmed: item.status == .closed && !item.isCompleted
        }
    }

    private func count(for filter: DoctorQueueFilter) -> Int {
        state.cases.filter { item in
            guard let selectedAgencyName else { return true }
            return item.agencyName == selectedAgencyName
        }.filter { item in
            switch filter {
            case .all: true
            case .waiting: item.status == .waiting && !item.isCompleted
            case .answered: item.status == .answered && !item.isCompleted
            case .confirmed: item.status == .closed && !item.isCompleted
            }
        }.count
    }
}

private struct DoctorWorkCard: View {
    let item: ConsultationCase
    let unreadNotificationCount: Int
    var isSelected = false
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
                    CaseUnreadBadge(count: unreadNotificationCount)
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

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)

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
            .background(
                isSelected ? AppTheme.brand.opacity(0.11) : AppTheme.surfaceStrong,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(statusColor)
                    .frame(width: 5)
                    .padding(.leading, 5)
                    .padding(.vertical, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppTheme.brand : AppTheme.border, lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(
                color: isSelected ? AppTheme.brand.opacity(0.18) : AppTheme.ink.opacity(0.04),
                radius: isSelected ? 11 : 8,
                y: 3
            )
            .contentShape(RoundedRectangle(cornerRadius: 20))
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
        !item.isCompleted && item.status == .waiting && Date().timeIntervalSince(item.uploadedAt) >= 86_400
    }

    private var statusTitle: String {
        if item.isCompleted { return "Closed" }
        return switch item.status {
        case .waiting: isOverdue ? "In Review · overdue" : "In Review"
        case .answered: "Waiting for Agent"
        case .closed: "Confirmed"
        }
    }

    private var statusColor: Color {
        if item.isCompleted { return AppTheme.muted }
        return switch item.status {
        case .waiting: Color(red: 0.78, green: 0.16, blue: 0.14)
        case .answered: AppTheme.accent
        case .closed: Color(red: 0.08, green: 0.52, blue: 0.32)
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
        case .waiting: Color(red: 0.78, green: 0.16, blue: 0.14)
        case .answered: AppTheme.accent
        case .closed: Color(red: 0.08, green: 0.52, blue: 0.32)
        }
    }
}
