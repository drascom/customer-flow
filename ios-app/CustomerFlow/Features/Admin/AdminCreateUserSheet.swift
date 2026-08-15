import SwiftUI

struct AdminCreateUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var password = ""
    @State private var role: UserRole = .agent
    @State private var agencyID = ""
    @State private var isSaving = false

    let agencies: [AdminAgency]
    let onCreate: (String, String, UserRole, String, String?) async -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    field("Full name", placeholder: "Display name", text: $displayName)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Username")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                        HStack {
                            Text("@\(suggestedUsername.isEmpty ? "generated.automatically" : suggestedUsername)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(suggestedUsername.isEmpty ? AppTheme.muted : AppTheme.ink)
                            Spacer()
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(AppTheme.brand)
                        }
                        .padding(12)
                        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        Text("Generated from the full name. A number is added automatically if it is already used.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Temporary password")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                        SecureField("At least 10 characters", text: $password)
                            .textContentType(.newPassword)
                            .padding(12)
                            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Role")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                        Picker("Role", selection: $role) {
                            ForEach(UserRole.allCases) { role in Text(role.title).tag(role) }
                        }
                        .pickerStyle(.segmented)
                    }

                    if role == .agent {
                        Menu {
                            ForEach(agencies.filter(\.active)) { agency in
                                Button(agency.name) { agencyID = agency.id }
                            }
                        } label: {
                            HStack {
                                Text(agencies.first(where: { $0.id == agencyID })?.name ?? "Select agency")
                                    .foregroundStyle(agencyID.isEmpty ? AppTheme.muted : AppTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .padding(12)
                            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }

                    Button {
                        Task {
                            isSaving = true
                            let created = await onCreate(
                                "",
                                displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                role,
                                password,
                                role == .agent ? agencyID : nil
                            )
                            if created { dismiss() }
                            isSaving = false
                        }
                    } label: {
                        HStack {
                            if isSaving { ProgressView() }
                            Text("Create user")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady || isSaving)
                    .padding(.top, 6)
                }
                .padding(18)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("New user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isReady: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 10
            && (role != .agent || !agencyID.isEmpty)
    }

    private var suggestedUsername: String {
        let transliterated = displayName
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "I")
        let folded = transliterated
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(title == "Username" ? .never : .words)
                .autocorrectionDisabled(title == "Username")
                .padding(12)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }
}

struct AdminEditUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var username: String
    @State private var password = ""
    @State private var role: UserRole
    @State private var agencyID: String
    @State private var isSaving = false

    let user: AdminUser
    let agencies: [AdminAgency]
    let onSave: (String, String, UserRole, String?, String?) async -> Bool

    init(
        user: AdminUser,
        agencies: [AdminAgency],
        onSave: @escaping (String, String, UserRole, String?, String?) async -> Bool
    ) {
        self.user = user
        self.agencies = agencies
        self.onSave = onSave
        _displayName = State(initialValue: user.displayName)
        _username = State(initialValue: user.username)
        _role = State(initialValue: user.role)
        _agencyID = State(initialValue: user.agencyID ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    editField("Display name", placeholder: "Display name", text: $displayName)
                    editField("Username", placeholder: "Username", text: $username)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Role")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                        Picker("Role", selection: $role) {
                            ForEach(UserRole.allCases) { role in Text(role.title).tag(role) }
                        }
                        .pickerStyle(.segmented)
                        Text("A role with consultation history cannot be changed.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    if role == .agent {
                        Menu {
                            ForEach(agencies.filter(\.active)) { agency in
                                Button(agency.name) { agencyID = agency.id }
                            }
                        } label: {
                            HStack {
                                Text(agencies.first(where: { $0.id == agencyID })?.name ?? "Select agency")
                                    .foregroundStyle(agencyID.isEmpty ? AppTheme.muted : AppTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .padding(12)
                            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("New temporary password (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                        SecureField("Leave blank to keep current password", text: $password)
                            .textContentType(.newPassword)
                            .padding(12)
                            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    Button {
                        Task {
                            isSaving = true
                            let trimmedPassword = password.isEmpty ? nil : password
                            let saved = await onSave(
                                username.trimmingCharacters(in: .whitespacesAndNewlines),
                                displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                role,
                                trimmedPassword,
                                role == .agent ? agencyID : nil
                            )
                            if saved { dismiss() }
                            isSaving = false
                        }
                    } label: {
                        HStack {
                            if isSaving { ProgressView() }
                            Text("Save changes")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady || isSaving)
                }
                .padding(18)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Edit user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isReady: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.contains(where: \.isWhitespace)
            && (password.isEmpty || password.count >= 10)
            && (role != .agent || !agencyID.isEmpty)
    }

    private func editField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(title == "Username" ? .never : .words)
                .autocorrectionDisabled(title == "Username")
                .padding(12)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }
}
