import SwiftUI
import UIKit

struct AdminCreateAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false

    let onCreate: (String) async -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Agency name")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                TextField("Enter agency name", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(13)
                    .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task {
                        isSaving = true
                        if await onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                        isSaving = false
                    }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("Create agency")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSaving)

                Spacer()
            }
            .padding(18)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("New agency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AdminAgencyManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewAgency = false
    @State private var editingAgency: AdminAgency?

    let agencies: [AdminAgency]
    let onCreate: (String) async -> Bool
    let onUpdate: (AdminAgency, String) async -> Bool
    let onFetchMCP: (AdminAgency) async -> AdminMCPConnection?
    let onRotateMCP: (AdminAgency) async -> AdminMCPConnection?

    var body: some View {
        NavigationStack {
            List(agencies) { agency in
                HStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .foregroundStyle(AppTheme.brand)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.brand.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agency.name)
                            .font(.headline)
                        Text("\(agency.userCount) linked user\(agency.userCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        Label(
                            agency.mcpConfigured ? "MCP connected" : "MCP not configured",
                            systemImage: agency.mcpConfigured ? "checkmark.shield" : "shield.slash"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(agency.mcpConfigured ? AppTheme.brand : AppTheme.muted)
                    }
                    Spacer()
                    Button("Edit") { editingAgency = agency }
                        .buttonStyle(.bordered)
                }
                .listRowBackground(AppTheme.surfaceStrong)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Agencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showsNewAgency = true }
                }
            }
        }
        .sheet(isPresented: $showsNewAgency) {
            AdminCreateAgencySheet(onCreate: onCreate)
        }
        .sheet(item: $editingAgency) { agency in
            AdminEditAgencySheet(
                agency: agency,
                onSave: { name in await onUpdate(agency, name) },
                onFetchMCP: { await onFetchMCP(agency) },
                onRotateMCP: { await onRotateMCP(agency) }
            )
        }
    }
}

private struct AdminEditAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var isLoadingMCP = false
    @State private var showsRotateConfirmation = false
    @State private var connection: AdminMCPConnection?
    @State private var oneTimeToken: String?

    let agency: AdminAgency
    let onSave: (String) async -> Bool
    let onFetchMCP: () async -> AdminMCPConnection?
    let onRotateMCP: () async -> AdminMCPConnection?

    init(
        agency: AdminAgency,
        onSave: @escaping (String) async -> Bool,
        onFetchMCP: @escaping () async -> AdminMCPConnection?,
        onRotateMCP: @escaping () async -> AdminMCPConnection?
    ) {
        self.agency = agency
        self.onSave = onSave
        self.onFetchMCP = onFetchMCP
        self.onRotateMCP = onRotateMCP
        _name = State(initialValue: agency.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                Text("Agency name")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                TextField("Enter agency name", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(13)
                    .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task {
                        isSaving = true
                        if await onSave(name.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSaving)

                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MCP connection")
                            .font(.headline)
                        Text("Give this endpoint and token only to the agency's approved system administrator. The token can access this agency's patient data.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)

                        if isLoadingMCP && connection == nil {
                            ProgressView("Loading connection…")
                        } else if let connection {
                            Label(
                                connection.configured ? "Active" : "Not configured",
                                systemImage: connection.configured ? "checkmark.shield.fill" : "shield.slash"
                            )
                            .foregroundStyle(connection.configured ? AppTheme.brand : AppTheme.muted)
                            Text(connection.endpointURL)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12))
                        }

                        if let oneTimeToken {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Copy this token now. It will not be shown again.")
                                    .font(.caption.weight(.semibold))
                                Text(oneTimeToken)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Button("Copy token", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = oneTimeToken
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button(
                            connection?.configured == true ? "Rotate access token" : "Generate access token",
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            showsRotateConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingMCP)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Edit agency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            isLoadingMCP = true
            connection = await onFetchMCP()
            isLoadingMCP = false
        }
        .confirmationDialog(
            connection?.configured == true ? "Rotate MCP access token?" : "Generate MCP access token?",
            isPresented: $showsRotateConfirmation,
            titleVisibility: .visible
        ) {
            Button(connection?.configured == true ? "Rotate token" : "Generate token", role: connection?.configured == true ? .destructive : nil) {
                Task {
                    isLoadingMCP = true
                    if let updated = await onRotateMCP() {
                        connection = updated
                        oneTimeToken = updated.accessToken
                    }
                    isLoadingMCP = false
                }
            }
        } message: {
            Text("Rotating immediately invalidates the previous token. Active agency integrations must be updated with the new token.")
        }
        .presentationDetents([.large])
    }
}
