import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AdminCreateAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var websiteURL = ""
    @State private var isSaving = false
    @State private var localError: String?

    let onCreate: (String, String?) async -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel("Agency name")
                TextField("Enter agency name", text: $name)
                    .textInputAutocapitalization(.words)
                    .inputStyle()

                fieldLabel("Website URL (optional)")
                TextField("https://agency.example", text: $websiteURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .inputStyle()
                Text("The ready-made patient form will automatically allow this website origin.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

                Button {
                    Task {
                        isSaving = true
                        let website = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if await onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), website.isEmpty ? nil : website) {
                            dismiss()
                        } else {
                            localError = "The agency could not be created. Check the details and try again."
                        }
                        isSaving = false
                    }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("Create agency and form")
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Agency could not be created", isPresented: Binding(
            get: { localError != nil },
            set: { if !$0 { localError = nil } }
        )) {
            Button("OK", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.ink)
    }
}

struct AdminAgencyManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewAgency = false
    @State private var editingAgency: AdminAgency?

    let agencies: [AdminAgency]
    let intakeForms: [AdminIntakeForm]
    let onCreate: (String, String?) async -> Bool
    let onSave: (AdminAgency, String, AdminIntakeForm?, [String]) async -> Bool
    let onSetFormActive: (AdminIntakeForm, Bool) async -> AdminIntakeForm?
    let onDelete: (AdminAgency) async -> String?
    let onFetchMCP: (AdminAgency) async -> AdminMCPConnection?
    let onRotateMCP: (AdminAgency) async -> AdminMCPConnection?
    let onExportGuide: (AdminAgency, String?) async -> Data?

    var body: some View {
        NavigationStack {
            List(agencies) { agency in
                HStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .foregroundStyle(agency.active ? AppTheme.brand : AppTheme.muted)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.brand.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(agency.name).font(.headline)
                            if !agency.active {
                                Text("INACTIVE").font(.caption2.bold()).foregroundStyle(.secondary)
                            }
                        }
                        Text("\(agency.userCount) linked user\(agency.userCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                        Label(
                            agency.mcpConfigured ? "MCP connected" : "MCP not configured",
                            systemImage: agency.mcpConfigured ? "checkmark.shield" : "shield.slash"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(agency.mcpConfigured ? AppTheme.brand : AppTheme.muted)
                    }
                    Spacer()
                    Button("Manage") { editingAgency = agency }.buttonStyle(.bordered)
                }
                .listRowBackground(AppTheme.surfaceStrong)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Agencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showsNewAgency = true }
                }
            }
        }
        .sheet(isPresented: $showsNewAgency) { AdminCreateAgencySheet(onCreate: onCreate) }
        .sheet(item: $editingAgency) { agency in
            let form = intakeForms.first { $0.agencyID == agency.id && $0.label == "Hair transplant assessment" }
                ?? intakeForms.first { $0.agencyID == agency.id }
            AdminEditAgencySheet(
                agency: agency,
                form: form,
                onSave: { name, currentForm, origins in await onSave(agency, name, currentForm, origins) },
                onSetFormActive: { currentForm, active in await onSetFormActive(currentForm, active) },
                onDelete: { await onDelete(agency) },
                onFetchMCP: { await onFetchMCP(agency) },
                onRotateMCP: { await onRotateMCP(agency) },
                onExportGuide: { token in await onExportGuide(agency, token) }
            )
        }
    }
}

private struct AdminEditAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var name: String
    @State private var allowedOrigins: String
    @State private var intakeForm: AdminIntakeForm?
    @State private var isSaving = false
    @State private var isUpdatingForm = false
    @State private var isLoadingMCP = false
    @State private var isExporting = false
    @State private var showsRotateConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var connection: AdminMCPConnection?
    @State private var oneTimeToken: String?
    @State private var exportDocument = AgencyIntegrationDocument()
    @State private var showsPDFExporter = false
    @State private var localError: String?

    let agency: AdminAgency
    let onSave: (String, AdminIntakeForm?, [String]) async -> Bool
    let onSetFormActive: (AdminIntakeForm, Bool) async -> AdminIntakeForm?
    let onDelete: () async -> String?
    let onFetchMCP: () async -> AdminMCPConnection?
    let onRotateMCP: () async -> AdminMCPConnection?
    let onExportGuide: (String?) async -> Data?

    init(
        agency: AdminAgency,
        form: AdminIntakeForm?,
        onSave: @escaping (String, AdminIntakeForm?, [String]) async -> Bool,
        onSetFormActive: @escaping (AdminIntakeForm, Bool) async -> AdminIntakeForm?,
        onDelete: @escaping () async -> String?,
        onFetchMCP: @escaping () async -> AdminMCPConnection?,
        onRotateMCP: @escaping () async -> AdminMCPConnection?,
        onExportGuide: @escaping (String?) async -> Data?
    ) {
        self.agency = agency
        self.onSave = onSave
        self.onSetFormActive = onSetFormActive
        self.onDelete = onDelete
        self.onFetchMCP = onFetchMCP
        self.onRotateMCP = onRotateMCP
        self.onExportGuide = onExportGuide
        _name = State(initialValue: agency.name)
        _intakeForm = State(initialValue: form)
        _allowedOrigins = State(initialValue: form?.allowedOrigins.joined(separator: "\n") ?? "")
    }

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            navigationContent
                .frame(minWidth: 980, idealWidth: 1_100, maxWidth: 1_260, minHeight: 660, idealHeight: 760)
            #else
            navigationContent
            #endif
        }
        .task {
            isLoadingMCP = true
            connection = await onFetchMCP()
            if connection == nil { localError = "The MCP connection details could not be loaded." }
            isLoadingMCP = false
        }
        .confirmationDialog(
            connection?.configured == true ? "Rotate MCP access token?" : "Generate MCP access token?",
            isPresented: $showsRotateConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                connection?.configured == true ? "Rotate token" : "Generate token",
                role: connection?.configured == true ? .destructive : nil
            ) {
                Task {
                    isLoadingMCP = true
                    if let updated = await onRotateMCP() {
                        connection = updated
                        oneTimeToken = updated.accessToken
                    } else {
                        localError = "The MCP access token could not be updated."
                    }
                    isLoadingMCP = false
                }
            }
        } message: {
            Text("Rotating immediately invalidates the previous token. Update any active agency integration with the new token.")
        }
        .confirmationDialog("Remove \(agency.name)?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Remove agency", role: .destructive) {
                Task {
                    if await onDelete() != nil {
                        dismiss()
                    } else {
                        localError = "The agency could not be removed."
                    }
                }
            }
        } message: {
            Text("An unused agency is deleted. An agency with users or patient history is deactivated and can no longer be selected.")
        }
        .fileExporter(
            isPresented: $showsPDFExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: "\(safeFilename(agency.name))-integration-guide.pdf"
        ) { result in
            if case .failure(let error) = result { localError = error.localizedDescription }
        }
        .alert("Action failed", isPresented: Binding(
            get: { localError != nil },
            set: { if !$0 { localError = nil } }
        )) {
            Button("OK", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
        .presentationDetents([.large])
    }

    private var navigationContent: some View {
        NavigationStack {
            ScrollView {
                Group {
                    #if targetEnvironment(macCatalyst)
                    HStack(alignment: .top, spacing: 18) {
                        patientFormDetails.frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(spacing: 18) {
                            agencyDetails
                            mcpDetails
                        }
                        .frame(maxWidth: 440, alignment: .topLeading)
                    }
                    #else
                    VStack(alignment: .leading, spacing: 18) {
                        agencyDetails
                        patientFormDetails
                        mcpDetails
                    }
                    #endif
                }
            }
            .padding(18)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Manage agency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var agencyDetails: some View {
        card {
            Text("Agency details").font(.headline)
            fieldLabel("Agency name")
            TextField("Enter agency name", text: $name)
                .textInputAutocapitalization(.words)
                .inputStyle()
            Button {
                Task {
                    isSaving = true
                    if await onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), intakeForm, parsedOrigins) {
                        dismiss()
                    } else {
                        localError = "The agency changes could not be saved. Check the website origins and try again."
                    }
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
            Button("Remove agency", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    private var patientFormDetails: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Patient application form").font(.headline)
                    Text(intakeForm?.label ?? "No form available").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if let intakeForm {
                    Label(
                        intakeForm.active ? "Active" : "Paused",
                        systemImage: intakeForm.active ? "checkmark.circle.fill" : "pause.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(intakeForm.active ? AppTheme.brand : .orange)
                }
            }

            if let intakeForm {
                fieldLabel("Allowed website origins")
                TextEditor(text: $allowedOrigins)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 76)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12))
                Text("One origin per line, for example https://agency.example")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
                copyRow("Direct link", value: intakeForm.directURL)
                copyRow("Iframe code", value: intakeForm.iframeCode, multiline: true)
                copyRow("JavaScript embed", value: intakeForm.javascriptCode, multiline: true)

                HStack {
                    Button("Preview", systemImage: "arrow.up.right.square") {
                        if let url = URL(string: intakeForm.directURL) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!intakeForm.active)
                    Spacer()
                    Button(
                        intakeForm.active ? "Pause form" : "Activate form",
                        systemImage: intakeForm.active ? "pause.fill" : "play.fill"
                    ) {
                        Task {
                            isUpdatingForm = true
                            if let updated = await onSetFormActive(intakeForm, !intakeForm.active) {
                                self.intakeForm = updated
                            } else {
                                localError = "The patient form status could not be changed."
                            }
                            isUpdatingForm = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdatingForm)
                }
            } else {
                Text("This agency does not yet have a patient application form.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var mcpDetails: some View {
        card {
            Text("MCP connection").font(.headline)
            Text("Share the endpoint, token and PDF guide only with the agency's approved system administrator.")
                .font(.caption).foregroundStyle(AppTheme.muted)
            if isLoadingMCP && connection == nil {
                ProgressView("Loading connection…")
            } else if let connection {
                Label(
                    connection.configured ? "Active" : "Not configured",
                    systemImage: connection.configured ? "checkmark.shield.fill" : "shield.slash"
                )
                .foregroundStyle(connection.configured ? AppTheme.brand : AppTheme.muted)
                copyRow("Endpoint", value: connection.endpointURL)
            }
            if let oneTimeToken {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Copy this token now. It will not be shown again.").font(.caption.weight(.semibold))
                    Text(oneTimeToken).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Copy token", systemImage: "doc.on.doc") { UIPasteboard.general.string = oneTimeToken }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            Button(
                connection?.configured == true ? "Rotate access token" : "Generate access token",
                systemImage: "arrow.triangle.2.circlepath"
            ) { showsRotateConfirmation = true }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingMCP)
            Button("Export integration PDF", systemImage: "doc.richtext") {
                Task {
                    isExporting = true
                    if let data = await onExportGuide(oneTimeToken) {
                        exportDocument = AgencyIntegrationDocument(data: data)
                        showsPDFExporter = true
                    } else {
                        localError = "The integration PDF could not be generated."
                    }
                    isExporting = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExporting || isLoadingMCP)
        }
    }

    private var parsedOrigins: [String] {
        allowedOrigins
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func copyRow(_ title: String, value: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(multiline ? 4 : 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: multiline ? 54 : 24, alignment: .topLeading)
                Button { UIPasteboard.general.string = value } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Copy \(title)")
            }
            .padding(10)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceStrong.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.ink)
    }

    private func safeFilename(_ value: String) -> String {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-").lowercased()
    }
}

private struct AgencyIntegrationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension View {
    func inputStyle() -> some View {
        padding(13)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
