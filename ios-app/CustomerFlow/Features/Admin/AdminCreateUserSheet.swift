import SwiftUI

struct AdminCreateUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var username = ""
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
                    field("Username", placeholder: "Username", text: $username)

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
                                username.trimmingCharacters(in: .whitespacesAndNewlines),
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
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.contains(where: \.isWhitespace)
            && password.count >= 10
            && (role != .agent || !agencyID.isEmpty)
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
