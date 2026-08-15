import SwiftUI

struct PatientMatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let candidate: PatientMatchCandidate
    let onOpenExisting: () -> Void
    let onSamePatient: () -> Void
    let onDifferentPatient: () -> Void
    @State private var screen: Screen = .possibleMatch
    @State private var photoIndex = 0
    @State private var showPhotoViewer = false

    private enum Screen: Equatable {
        case possibleMatch
        case confirmDifferent
        case existingConsultation
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(navigationTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if screen != .existingConsultation {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 18) {
                    switch screen {
                    case .possibleMatch:
                        possibleMatch
                    case .confirmDifferent:
                        differentPatientConfirmation
                    case .existingConsultation:
                        existingConsultation
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPhotoViewer) {
            ConfidentialPhotoViewer(
                photoCount: max(candidate.photoCount, 1),
                selectedIndex: $photoIndex
            )
        }
    }

    private var navigationTitle: String {
        switch screen {
        case .possibleMatch: "Possible Patient Match"
        case .confirmDifferent: "Confirm Different Patient"
        case .existingConsultation: "Consultation Found"
        }
    }

    private var possibleMatch: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.brand.opacity(0.75))
                    .frame(width: 64, height: 64)
                    .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name).font(.headline)
                    if candidate.createdByAnotherAgent {
                        Text("Previous consultation found")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    } else {
                        Text("Your existing patient · \(candidate.id)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))

            confidentialGallery

            if candidate.createdByAnotherAgent {
                Text("This patient may already be registered and has previously received a consultation.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Is this the same patient?")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Yes — Same Patient") {
                    screen = .existingConsultation
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("No — Different Patient") { screen = .confirmDifferent }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            } else {
                Text("This patient is already in your records.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.brandDark)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Open Patient") {
                    dismiss()
                    onOpenExisting()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var confidentialGallery: some View {
        ZStack {
            TabView(selection: $photoIndex) {
                ForEach(0..<max(candidate.photoCount, 1), id: \.self) { index in
                    ConfidentialClinicalPhoto(index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PhotoNavigationArrows(
                selectedIndex: $photoIndex,
                photoCount: max(candidate.photoCount, 1)
            )
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomLeading) {
            Button {
                showPhotoViewer = true
            } label: {
                Label("Enlarge", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.68), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(photoIndex + 1) / \(max(candidate.photoCount, 1))")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    private var existingConsultation: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.brand)
            Text("Consultation already exists")
                .font(.title3.bold())
            Text("This patient already has a consultation record. No new case has been created.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.muted)
            Button("Back to Cases") {
                dismiss()
                onSamePatient()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var differentPatientConfirmation: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.brand)
            Text("Confirm that you checked the profile photo and this is a different person. The decision will be recorded and may be verified later.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.muted)
            Button("Continue with New Patient") {
                dismiss()
                onDifferentPatient()
            }
            .buttonStyle(.borderedProminent)
            Button("Back to Possible Match") { screen = .possibleMatch }
                .buttonStyle(.bordered)
        }
    }
}

private struct ConfidentialClinicalPhoto: View {
    let index: Int

    var body: some View {
        PhotoUnavailableView()
            .overlay(alignment: .center) {
                Text("CONFIDENTIAL · DO NOT SHARE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.88))
            }
    }
}

private struct ConfidentialPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photoCount: Int
    @Binding var selectedIndex: Int

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(0..<photoCount, id: \.self) { index in
                    ConfidentialClinicalPhoto(index: index)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 12)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            PhotoNavigationArrows(
                selectedIndex: $selectedIndex,
                photoCount: photoCount
            )
            .padding(.horizontal, 8)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.68), in: Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}

private struct PhotoNavigationArrows: View {
    @Binding var selectedIndex: Int
    let photoCount: Int

    var body: some View {
        if photoCount > 1 {
            HStack {
                navigationButton(
                    systemName: "chevron.left",
                    label: "Previous photo",
                    isEnabled: selectedIndex > 0
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIndex -= 1
                    }
                }

                Spacer()

                navigationButton(
                    systemName: "chevron.right",
                    label: "Next photo",
                    isEnabled: selectedIndex < photoCount - 1
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIndex += 1
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func navigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(isEnabled ? 0.62 : 0.28), in: Circle())
                .overlay(Circle().stroke(.white.opacity(isEnabled ? 0.42 : 0.16)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
