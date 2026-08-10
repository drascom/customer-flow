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
