import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var tourModel: AppTourModel
    @State private var showsProfile = false
    @State private var showsNotifications = false

    var body: some View {
        Group {
            if state.phase == .authenticated {
                NavigationStack {
                    Group {
                        switch state.role {
                        case .doctor:
                            DoctorQueueView()
                        case .agent:
                            AgentCasesView()
                        case .admin, .manager:
                            if let repository = state.adminRepository, let user = state.currentUser {
                                AdminDashboardView(
                                    repository: repository,
                                    currentUserID: user.id,
                                    isReadOnly: user.role == .manager,
                                    liveRevision: state.liveRevision,
                                    notificationCaseID: state.pendingNotificationCaseID,
                                    consumeNotificationCase: state.consumePendingNotificationCase
                                )
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        appHeader
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                OnboardingView()
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.brand)
        .overlay {
            if state.isRefreshingAfterForeground {
                ZStack {
                    AppTheme.background.opacity(0.82).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppTheme.brand)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView {
                guard let user = state.currentUser else { return }
                tourModel.showAgain(
                    userID: user.id,
                    serverAddress: state.savedServerAddress,
                    role: user.role
                )
            }
        }
        .sheet(isPresented: $showsNotifications) {
            NotificationCenterView(
                notifications: state.notifications,
                unreadCount: state.unreadNotificationCount,
                onMarkAllRead: { await state.markAllNotificationsRead() },
                onSelect: { notification in await state.openNotification(notification) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: $tourModel.isPresented) {
            AppTourView(model: tourModel)
        }
        .task(id: state.phase == .authenticated ? state.currentUser?.id : nil) {
            guard state.phase == .authenticated, let user = state.currentUser else { return }
            await tourModel.presentIfNeeded(
                userID: user.id,
                serverAddress: state.savedServerAddress,
                role: user.role
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await state.refreshAfterForeground() }
        }
        .alert("Something changed", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var appHeader: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .accessibilityLabel("Customer Flow logo")

            VStack(alignment: .leading, spacing: 0) {
                (
                    Text("C").font(.system(size: 20, weight: .bold))
                    + Text("ustomer ").font(.system(size: 20, weight: .light))
                    + Text("F").font(.system(size: 20, weight: .bold))
                    + Text("low").font(.system(size: 20, weight: .light))
                )
                .foregroundStyle(AppTheme.ink)

                Text("by NatChatt")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(AppTheme.muted)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Customer Flow by NatChatt")

            Spacer(minLength: 8)

            Button {
                showsNotifications = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: state.unreadNotificationCount > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 34, height: 34)
                    if state.unreadNotificationCount > 0 {
                        Text(state.unreadNotificationCount > 99 ? "99+" : "\(state.unreadNotificationCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
                .foregroundStyle(AppTheme.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "notifications.title", defaultValue: "Notifications"))

            Menu {
                if let user = state.currentUser {
                    Text(user.displayName)
                    Divider()
                }
                Button("Profile", systemImage: "person.crop.circle") {
                    showsProfile = true
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await state.logout() }
                }
                Button("Change server", systemImage: "server.rack") {
                    Task { await state.changeServer() }
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.brand)
                    .accessibilityLabel(state.role.title)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background.ignoresSafeArea(edges: .top))
    }
}

struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""
    @State private var profileMessage = ""
    @State private var passwordMessage = ""
    @State private var showsPasswordChangeConfirmation = false

    let onShowTour: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = state.currentUser {
                        LabeledContent("Username", value: user.username)
                        LabeledContent("Role", value: user.role.title)
                    }
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    if !profileMessage.isEmpty {
                        Label(profileMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.brandDark)
                    }
                    Button {
                        saveProfile()
                    } label: {
                        actionLabel("Save profile")
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || state.isWorking)
                }

                Section {
                    RevealablePasswordField(
                        "Current password",
                        text: $currentPassword,
                        textContentType: .password
                    )
                    RevealablePasswordField(
                        "New password",
                        text: $newPassword,
                        textContentType: .newPassword
                    )
                    RevealablePasswordField(
                        "Confirm new password",
                        text: $passwordConfirmation,
                        textContentType: .newPassword
                    )
                    if !passwordMessage.isEmpty {
                        Text(passwordMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        requestPasswordChange()
                    } label: {
                        actionLabel("Change password")
                    }
                    .disabled(currentPassword.isEmpty || newPassword.isEmpty || passwordConfirmation.isEmpty || state.isWorking)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Use at least 10 characters. After changing it, you will be signed out and must sign in with the new password.")
                }

                if state.role != .admin && state.role != .manager {
                    Section("Help") {
                        Button {
                            onShowTour()
                            dismiss()
                        } label: {
                            Label("Show app tour again", systemImage: "questionmark.circle")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(state.isWorking)
        .onAppear(perform: loadProfile)
        .alert("Change password and sign out?", isPresented: $showsPasswordChangeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Change & Sign Out", role: .destructive) {
                changePasswordAndSignOut()
            }
        } message: {
            Text("Your password will be changed immediately. You will then return to the sign-in screen and must use your new password.")
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if state.isWorking { ProgressView() }
            else { Image(systemName: "arrow.right") }
        }
        .font(.headline)
    }

    private func loadProfile() {
        guard let user = state.currentUser else { return }
        displayName = user.displayName
        email = user.email ?? ""
        phone = user.phone ?? ""
    }

    private func saveProfile() {
        profileMessage = ""
        Task {
            if await state.updateProfile(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ) {
                profileMessage = "Profile updated."
            }
        }
    }

    private func requestPasswordChange() {
        passwordMessage = ""
        guard newPassword.count >= 10 else {
            passwordMessage = "The new password must be at least 10 characters."
            return
        }
        guard newPassword == passwordConfirmation else {
            passwordMessage = "The passwords do not match."
            return
        }
        showsPasswordChangeConfirmation = true
    }

    private func changePasswordAndSignOut() {
        passwordMessage = ""
        Task {
            if await state.changePassword(currentPassword: currentPassword, newPassword: newPassword) {
                dismiss()
                await Task.yield()
                await state.logout()
            } else {
                passwordMessage = "The password could not be changed. Check your current password and try again."
            }
        }
    }
}
