import SwiftUI

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
            AdminEditAgencySheet(agency: agency) { name in
                await onUpdate(agency, name)
            }
        }
    }
}

private struct AdminEditAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false

    let agency: AdminAgency
    let onSave: (String) async -> Bool

    init(agency: AdminAgency, onSave: @escaping (String) async -> Bool) {
        self.agency = agency
        self.onSave = onSave
        _name = State(initialValue: agency.name)
    }

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

                Spacer()
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
        .presentationDetents([.medium])
    }
}
