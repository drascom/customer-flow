import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = "demo123"
    @State private var showsPasswordReset = false
    @FocusState private var focusedField: Field?

    private enum Field { case server, username, password }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    brand
                    content
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if serverAddress.isEmpty { serverAddress = state.savedServerAddress }
        }
        .animation(.easeInOut(duration: 0.2), value: state.phase)
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetView(initialIdentifier: username)
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                (
                    Text("C").font(.system(size: 26, weight: .bold))
                    + Text("ustomer ").font(.system(size: 26, weight: .light))
                    + Text("F").font(.system(size: 26, weight: .bold))
                    + Text("low").font(.system(size: 26, weight: .light))
                )
                .foregroundStyle(AppTheme.ink)

                Text("by NatChatt")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .restoring:
            VStack(spacing: 14) {
                ProgressView()
                Text("Connecting…")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 220)

        case .serverSetup:
            card {
                Text("Connect to server")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)

                TextField("https://server.example.com", text: $serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .focused($focusedField, equals: .server)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .textFieldStyle(.roundedBorder)

                Button(action: connect) {
                    actionLabel("Connect", systemImage: "arrow.right", loading: state.isWorking)
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isWorking)

                Text("Enter the address supplied by your organisation. The app checks the server before asking for your login.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

        case .login:
            card {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(state.connectedServerName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(signIn)
                    .textFieldStyle(.roundedBorder)

                Button(action: signIn) {
                    actionLabel("Sign in", systemImage: "arrow.right", loading: state.isWorking)
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || state.isWorking)

                Button("Forgot password?") {
                    focusedField = nil
                    showsPasswordReset = true
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)

                Button("Change server") {
                    Task { await state.changeServer() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)

                Text("Accounts are created by your server administrator. There is no public registration in the app.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

        case .authenticated:
            EmptyView()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(20)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.border))
    }

    private func actionLabel(_ title: String, systemImage: String, loading: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if loading { ProgressView().tint(AppTheme.accentInk) }
            else { Image(systemName: systemImage) }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 32)
    }

    private func connect() {
        guard !state.isWorking else { return }
        focusedField = nil
        Task { _ = await state.connect(serverAddress: serverAddress) }
    }

    private func signIn() {
        guard !state.isWorking else { return }
        focusedField = nil
        Task {
            _ = await state.login(username: username, password: password)
        }
    }
}

struct PasswordResetView: View {
    private enum Step { case request, verify, complete }

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var identifier: String
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var step: Step = .request
    @State private var deliveryMessage = ""
    @State private var formError = ""

    init(initialIdentifier: String = "") {
        _identifier = State(initialValue: initialIdentifier)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .request:
                    Section {
                        TextField("Username or email", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                    } footer: {
                        Text("We will send a six-digit verification code to the email saved in your profile.")
                    }
                    Section {
                        Button {
                            requestCode()
                        } label: {
                            actionLabel("Send reset code")
                        }
                        .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isWorking)
                    }

                case .verify:
                    Section {
                        Text(deliveryMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Section {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                        SecureField("Confirm new password", text: $confirmation)
                            .textContentType(.newPassword)
                        if !formError.isEmpty {
                            Text(formError).font(.caption).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Verification")
                    } footer: {
                        Text("Use at least 10 characters. The code expires after 10 minutes.")
                    }
                    Section {
                        Button {
                            confirmReset()
                        } label: {
                            actionLabel("Reset password")
                        }
                        .disabled(code.count != 6 || newPassword.isEmpty || confirmation.isEmpty || state.isWorking)
                        Button("Send another code") {
                            code = ""
                            formError = ""
                            step = .request
                        }
                    }

                case .complete:
                    Section {
                        Label("Your password has been updated.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.brandDark)
                        Text("You can now sign in with your new password.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                        Button("Done") { dismiss() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(state.isWorking)
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

    private func requestCode() {
        formError = ""
        Task {
            if let message = await state.requestPasswordReset(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines)) {
                deliveryMessage = message
                step = .verify
            }
        }
    }

    private func confirmReset() {
        formError = ""
        guard newPassword.count >= 10 else {
            formError = "The password must be at least 10 characters."
            return
        }
        guard newPassword == confirmation else {
            formError = "The passwords do not match."
            return
        }
        Task {
            if await state.resetPassword(
                identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code,
                newPassword: newPassword
            ) {
                step = .complete
                code = ""
                newPassword = ""
                confirmation = ""
            }
        }
    }
}
