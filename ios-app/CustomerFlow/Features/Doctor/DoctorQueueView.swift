import SwiftUI

struct DoctorQueueView: View {
    @EnvironmentObject private var state: AppState
    @Bindable var tourModel: AppTourModel
    @State private var filter: DoctorQueueFilter = .myWaiting
    @State private var searchText = ""
    @State private var oldestFirst = true
    @State private var selectedCase: ConsultationCase?
    @State private var uploaderFilter: String?

    private var filteredCases: [ConsultationCase] {
        state.cases
            .filter(matchesQueue)
            .filter { item in
                guard let uploaderFilter else { return true }
                return item.agentName == uploaderFilter
            }
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [item.patient.name, item.reference, item.agentName, item.agentNote]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { oldestFirst ? $0.uploadedAt < $1.uploadedAt : $0.uploadedAt > $1.uploadedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(spacing: 10) {
                        filterMenu
                        if let uploaderFilter {
                            uploaderFilterBanner(uploaderFilter)
                        }
                        caseGrid
                    }
                    .padding(.horizontal, 12)
                } header: {
                    searchHeader
                }
            }
            .padding(.bottom, 16)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCase) { item in
            CaseDetailView(caseID: item.id)
                .environmentObject(state)
        }
        .refreshable { await state.load() }
        .overlayPreferenceValue(AppTourAnchorPreferenceKey.self) { anchors in
            AppTourView(model: tourModel, anchors: anchors)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Search", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: 620, minHeight: 42)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.background)
    }

    private var filterMenu: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(DoctorQueueFilter.allCases) { item in
                    Button {
                        filter = item
                        uploaderFilter = nil
                    } label: {
                        Label("\(item.title)  ·  \(count(for: item))", systemImage: filter == item ? "checkmark" : "circle")
                    }
                }
            } label: {
                ZStack {
                    HStack(spacing: 7) {
                        Text(filter.title)
                        Text("\(count(for: filter))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppTheme.accentInk.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentInk)
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .appTourAnchor(.doctorFilter)

            Button {
                oldestFirst.toggle()
            } label: {
                Label(oldestFirst ? "Oldest" : "Newest", systemImage: oldestFirst ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 34)
                    .background(AppTheme.surfaceStrong, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(oldestFirst ? "Oldest first" : "Newest first")
            .appTourAnchor(.doctorSort)
        }
        .padding(.vertical, 7)
    }

    private var caseGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
            ForEach(Array(filteredCases.enumerated()), id: \.element.id) { index, item in
                CaseCardView(item: item, tourTarget: index == 0 ? .doctorCase : nil) {
                    selectedCase = item
                } onAgentFilter: {
                    uploaderFilter = item.agentName
                }
            }
        }
        .overlay {
            if filteredCases.isEmpty {
                ContentUnavailableView("No cases", systemImage: "tray", description: Text("No cases match this view."))
                    .frame(minHeight: 280)
            }
        }
    }

    private func uploaderFilterBanner(_ name: String) -> some View {
        HStack {
            Text("Posts by **\(name)**")
            Spacer()
            Button("Clear", systemImage: "xmark") { uploaderFilter = nil }
                .font(.caption.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.brandDark)
        .padding(12)
        .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func matchesQueue(_ item: ConsultationCase) -> Bool {
        switch filter {
        case .all: true
        case .myWaiting: item.status == .waiting && item.assignedDoctorID == state.currentDoctorID
        case .unassigned: item.status == .waiting && item.assignedDoctorID == nil
        case .answered: item.status == .answered && item.assignedDoctorID == state.currentDoctorID
        case .closed: item.status == .closed && item.assignedDoctorID == state.currentDoctorID
        }
    }

    private func count(for filter: DoctorQueueFilter) -> Int {
        state.cases.filter { item in
            switch filter {
            case .all: true
            case .myWaiting: item.status == .waiting && item.assignedDoctorID == state.currentDoctorID
            case .unassigned: item.status == .waiting && item.assignedDoctorID == nil
            case .answered: item.status == .answered && item.assignedDoctorID == state.currentDoctorID
            case .closed: item.status == .closed && item.assignedDoctorID == state.currentDoctorID
            }
        }.count
    }
}

private struct CaseCardView: View {
    let item: ConsultationCase
    let tourTarget: AppTourTarget?
    let onOpen: () -> Void
    let onAgentFilter: () -> Void
    @State private var photoIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Uploaded \(item.uploadedAt.formatted(.relative(presentation: .named)))")
                Spacer()
                Text(item.reference).fontWeight(.bold)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.muted)

            TabView(selection: $photoIndex) {
                ForEach(0..<item.photoCount, id: \.self) { index in
                    ClinicalPhotoView(photoID: item.photoID(at: index), index: index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .appTourAnchor(tourTarget)
            .overlay(alignment: .bottomTrailing) {
                Text("\(photoIndex + 1) / \(item.photoCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(10)
            }

            HStack(spacing: 8) {
                Text(item.patient.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(item.assignedDoctorID == nil ? "Unassigned" : "Assigned to you")
                    .font(.caption2.bold())
                    .foregroundStyle(item.assignedDoctorID == nil ? AppTheme.accent : AppTheme.brandDark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((item.assignedDoctorID == nil ? AppTheme.accent : AppTheme.brand).opacity(0.14), in: Capsule())
            }

            Text(item.agentNote)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                metric("Graft number", item.agentGrafts)
                metric("Price", "\(item.currency) \(item.agentPrice)")
            }

            Divider()
            HStack {
                StatusChip(status: item.status)
                Spacer()
                Button("by \(item.agentName)", action: onAgentFilter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(16)
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpen)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(AppTheme.muted)
            Text(value).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct StatusChip: View {
    let status: ConsultationStatus

    var body: some View {
        Label(status.title, systemImage: "circle.fill")
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .waiting: AppTheme.accent
        case .answered: AppTheme.brand
        case .closed: AppTheme.muted
        }
    }
}
