import SwiftUI

struct AdminDashboardView: View {
    @State private var model: AdminDashboardModel
    @State private var showsFilters = false
    @State private var showsNewUser = false
    @State private var showsNewAgency = false
    @State private var expandedCaseID: String?
    @State private var expandedUserID: String?
    @State private var pendingUser: AdminUser?
    @State private var pendingUserActive = false
    @State private var pendingUserDelete = false
    @State private var showsUserConfirmation = false
    @State private var pendingCase: AdminCase?
    @State private var pendingDoctorID = ""
    @State private var assignmentReason = ""
    @State private var showsAssignmentPrompt = false

    init(repository: any AdminRepository, currentUserID: String) {
        _model = State(initialValue: AdminDashboardModel(repository: repository, currentUserID: currentUserID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                Section {
                    overview
                    filters
                    content
                } header: {
                    controls
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .refreshable { await model.load() }
        .task { await model.load() }
        .sheet(isPresented: $showsNewUser) {
            AdminCreateUserSheet(agencies: model.agencies) { username, displayName, role, password, agencyID in
                await model.createUser(
                    username: username,
                    displayName: displayName,
                    role: role,
                    password: password,
                    agencyID: agencyID
                )
            }
        }
        .sheet(isPresented: $showsNewAgency) {
            AdminCreateAgencySheet { name in await model.createAgency(name: name) }
        }
        .confirmationDialog(userActionTitle, isPresented: $showsUserConfirmation, titleVisibility: .visible) {
            if let user = pendingUser {
                if pendingUserDelete {
                    Button("Delete \(user.displayName)", role: .destructive) {
                        Task { await model.deleteUser(user) }
                    }
                } else {
                    Button(pendingUserActive ? "Reactivate" : "Deactivate", role: pendingUserActive ? nil : .destructive) {
                        Task { await model.setUserActive(user, active: pendingUserActive) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingUserDelete {
                Text("Only inactive users without consultation history can be permanently deleted.")
            } else if !pendingUserActive {
                Text("The user will be signed out and will no longer be able to access the server.")
            }
        }
        .alert("Change assigned doctor", isPresented: $showsAssignmentPrompt) {
            TextField("Reason", text: $assignmentReason)
            Button("Cancel", role: .cancel) {}
            Button("Confirm") { confirmDoctorChange() }
        } message: {
            Text("A short reason is required when changing or removing an existing assignment.")
        }
        .alert("Admin action failed", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Admin section", selection: $model.selectedSection) {
                ForEach(AdminDashboardSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.selectedSection) {
                model.searchText = ""
                expandedCaseID = nil
                expandedUserID = nil
            }

            HStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.muted)
                    TextField(searchPlaceholder, text: $model.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsFilters.toggle() }
                } label: {
                    Image(systemName: model.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.brand)

                if model.selectedSection == .users {
                    Menu {
                        Button("New user", systemImage: "person.badge.plus") { showsNewUser = true }
                        Button("New agency", systemImage: "building.2.crop.circle") { showsNewAgency = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AppTheme.background)
    }

    private var overview: some View {
        HStack(spacing: 8) {
            if model.selectedSection == .cases {
                compactMetric(value: model.cases.count, label: "Cases")
                compactMetric(value: model.cases.filter { $0.status == .waiting }.count, label: "Waiting")
                compactMetric(value: model.cases.filter { $0.doctorID == nil }.count, label: "Unassigned")
            } else {
                compactMetric(value: model.users.count, label: "Users")
                compactMetric(value: model.users.filter(\.active).count, label: "Active")
                compactMetric(value: model.users.filter { $0.role == .doctor }.count, label: "Doctors")
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        if showsFilters {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if model.hasActiveFilters {
                        Button("Clear") { model.clearFilters() }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                if model.selectedSection == .cases {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            chip("All", selected: model.caseStatus.isEmpty) { model.caseStatus = "" }
                            chip("Waiting", selected: model.caseStatus == "waiting") { model.caseStatus = "waiting" }
                            chip("Answered", selected: model.caseStatus == "answered") { model.caseStatus = "answered" }
                            chip("Closed", selected: model.caseStatus == "closed") { model.caseStatus = "closed" }
                        }
                    }
                    HStack(spacing: 8) {
                        filterMenu(
                            title: assignmentTitle,
                            options: [("", "Any assignment"), ("assigned", "Assigned"), ("unassigned", "Unassigned")],
                            selection: $model.caseAssignment
                        )
                        filterMenu(
                            title: model.caseAgency.isEmpty ? "Agency" : model.caseAgency,
                            options: [("", "Any agency")] + model.agencies.map { ($0.name, $0.name) },
                            selection: $model.caseAgency
                        )
                    }
                    filterMenu(
                        title: doctorFilterTitle,
                        options: [("", "Any doctor")] + model.activeDoctors.map { ($0.id, $0.displayName) },
                        selection: $model.caseDoctorID
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            chip("All", selected: model.userRole.isEmpty) { model.userRole = "" }
                            chip("Agents", selected: model.userRole == "agent") { model.userRole = "agent" }
                            chip("Doctors", selected: model.userRole == "doctor") { model.userRole = "doctor" }
                            chip("Admins", selected: model.userRole == "admin") { model.userRole = "admin" }
                        }
                    }
                    HStack(spacing: 8) {
                        filterMenu(
                            title: userStatusTitle,
                            options: [("", "Any status"), ("active", "Active"), ("inactive", "Inactive")],
                            selection: $model.userStatus
                        )
                        filterMenu(
                            title: userAgencyTitle,
                            options: [("", "Any agency")] + model.agencies.map { ($0.id, $0.name) },
                            selection: $model.userAgencyID
                        )
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.cases.isEmpty && model.users.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else if model.selectedSection == .cases {
            if model.filteredCases.isEmpty {
                emptyState("No cases found", icon: "tray")
            } else {
                ForEach(model.filteredCases) { item in
                    AdminCaseCard(
                        item: item,
                        doctors: model.activeDoctors,
                        isExpanded: expandedCaseID == item.id,
                        onToggle: { withAnimation { expandedCaseID = expandedCaseID == item.id ? nil : item.id } },
                        onAssign: { requestAssignment(for: item, doctorID: $0) }
                    )
                }
            }
        } else if model.filteredUsers.isEmpty {
            emptyState("No users found", icon: "person.2")
        } else {
            ForEach(model.filteredUsers) { user in
                AdminUserCard(
                    user: user,
                    currentUserID: model.currentUserID,
                    isExpanded: expandedUserID == user.id,
                    onToggle: { withAnimation { expandedUserID = expandedUserID == user.id ? nil : user.id } },
                    onSetActive: { requestUserAction(user, active: $0, delete: false) },
                    onDelete: { requestUserAction(user, active: false, delete: true) }
                )
            }
        }
    }

    private var searchPlaceholder: String {
        model.selectedSection == .cases ? "Patient, ref, agent…" : "Name, username, agency…"
    }

    private var assignmentTitle: String {
        switch model.caseAssignment {
        case "assigned": "Assigned"
        case "unassigned": "Unassigned"
        default: "Assignment"
        }
    }

    private var doctorFilterTitle: String {
        model.activeDoctors.first(where: { $0.id == model.caseDoctorID })?.displayName ?? "Doctor"
    }

    private var userStatusTitle: String {
        switch model.userStatus {
        case "active": "Active"
        case "inactive": "Inactive"
        default: "Status"
        }
    }

    private var userAgencyTitle: String {
        model.agencies.first(where: { $0.id == model.userAgencyID })?.name ?? "Agency"
    }

    private var userActionTitle: String {
        guard let user = pendingUser else { return "Manage user" }
        if pendingUserDelete { return "Delete \(user.displayName)?" }
        return "\(pendingUserActive ? "Reactivate" : "Deactivate") \(user.displayName)?"
    }

    private func compactMetric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? AppTheme.accentInk : AppTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? AppTheme.accent : AppTheme.inset, in: Capsule())
            .buttonStyle(.plain)
    }

    private func filterMenu(title: String, options: [(String, String)], selection: Binding<String>) -> some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button {
                    selection.wrappedValue = option.0
                } label: {
                    if selection.wrappedValue == option.0 {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Spacer(minLength: 3)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30))
            Text(title).font(.headline)
            Text("Try changing the search or filters.")
                .font(.caption)
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func requestUserAction(_ user: AdminUser, active: Bool, delete: Bool) {
        pendingUser = user
        pendingUserActive = active
        pendingUserDelete = delete
        showsUserConfirmation = true
    }

    private func requestAssignment(for item: AdminCase, doctorID: String?) {
        guard doctorID != item.doctorID else { return }
        if item.doctorID != nil {
            pendingCase = item
            pendingDoctorID = doctorID ?? ""
            assignmentReason = ""
            showsAssignmentPrompt = true
        } else {
            Task { await model.assignDoctor(to: item, doctorID: doctorID, reason: "") }
        }
    }

    private func confirmDoctorChange() {
        guard let item = pendingCase else { return }
        let reason = assignmentReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            model.errorMessage = "Enter a reason before changing the assigned doctor."
            return
        }
        Task { await model.assignDoctor(to: item, doctorID: pendingDoctorID.isEmpty ? nil : pendingDoctorID, reason: reason) }
    }
}
