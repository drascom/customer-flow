import SwiftUI

struct DoctorQueueView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: DoctorQueueFilter = .waiting
    @State private var searchText = ""
    @State private var oldestFirst = true
    @State private var selectedCase: ConsultationCase?
    @State private var expandedCaseID: UUID?

    private var filteredCases: [ConsultationCase] {
        state.cases
            .filter(matchesQueue)
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [item.patient.name, item.reference, item.agencyName, item.agentName, item.agentNote]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { oldestFirst ? $0.uploadedAt < $1.uploadedAt : $0.uploadedAt > $1.uploadedAt }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 10) {
                            filterMenu
                            caseGrid(minimumEmptyHeight: max(320, proxy.size.height - 125))
                        }
                        .padding(.horizontal, 12)
                    } header: {
                        searchHeader
                    }
                }
                .padding(.bottom, 16)
            }
            .refreshable { await state.load() }
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCase) { item in
            CaseDetailView(caseID: item.id)
                .environmentObject(state)
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
                        expandedCaseID = nil
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
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func caseGrid(minimumEmptyHeight: CGFloat) -> some View {
        if filteredCases.isEmpty {
            ContentUnavailableView("No cases", systemImage: "tray", description: Text("No cases match this view."))
                .frame(maxWidth: .infinity, minHeight: minimumEmptyHeight)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                ForEach(filteredCases) { item in
                    CaseCardView(
                        item: item,
                        isCollapsible: item.status != .waiting,
                        isExpanded: item.status == .waiting || expandedCaseID == item.id,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                expandedCaseID = expandedCaseID == item.id ? nil : item.id
                            }
                        },
                        onOpen: { selectedCase = item }
                    )
                }
            }
        }
    }

    private func matchesQueue(_ item: ConsultationCase) -> Bool {
        switch filter {
        case .waiting: item.status == .waiting
        case .answered: item.status == .answered
        case .confirmed: item.status == .closed
        }
    }

    private func count(for filter: DoctorQueueFilter) -> Int {
        state.cases.filter { item in
            switch filter {
            case .waiting: item.status == .waiting
            case .answered: item.status == .answered
            case .confirmed: item.status == .closed
            }
        }.count
    }
}

private struct CaseCardView: View {
    let item: ConsultationCase
    let isCollapsible: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    @State private var photoIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            statusBand
                .onTapGesture {
                    if isCollapsible {
                        onToggle()
                    } else {
                        onOpen()
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isCollapsible {
                        Button(action: onToggle) {
                            summaryHeader
                        }
                        .buttonStyle(.plain)
                    } else {
                        summaryHeader
                    }
                }

                if isExpanded {
                    Divider().padding(.vertical, 12)

                    Group {
                        if item.photoCount == 0 {
                            NoPhotosView()
                        } else {
                            TabView(selection: $photoIndex) {
                                ForEach(0..<item.photoCount, id: \.self) { index in
                                    CasePhotoView(
                                        photoID: item.photoIDs.indices.contains(index) ? item.photoIDs[index] : nil,
                                        index: index
                                    )
                                    .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(photoIndex + 1) / \(item.photoCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding(10)
                            }
                        }
                    }
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(item.agentNote)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .padding(.top, 12)

                    HStack(spacing: 8) {
                        metric("Estimated grafts", item.agentGrafts)
                        metric("Estimated price", AppCurrency.amount(item.agentPrice))
                    }
                    .padding(.top, 12)

                    if let finalGrafts = item.finalGrafts,
                       let finalPrice = item.finalPrice {
                        HStack(spacing: 8) {
                            metric("Final grafts", finalGrafts)
                            metric("Final price", AppCurrency.amount(finalPrice))
                        }
                        .padding(.top, 8)
                    }

                    if isCollapsible {
                        Button("Open case", systemImage: "arrow.up.right.square", action: onOpen)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 12)
                    }
                }

                if let latestMessage {
                    Divider()
                        .padding(.top, isExpanded ? 14 : 8)
                        .padding(.bottom, 8)
                    LatestMessagePreview(
                        author: latestMessage.author,
                        text: latestMessage.text,
                        createdAt: latestMessage.createdAt,
                        hasPhoto: latestMessage.attachmentPhotoID != nil
                    )
                }
            }
            .padding(14)
        }
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.border))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if !isCollapsible {
                onOpen()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.patient.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(item.uploadedAt.compactRelativeText)
                    if isCollapsible {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 6) {
                Image(systemName: "building.2")
                Text(item.agencyName ?? "No agency")
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(item.agentName).lineLimit(1)
            }
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.muted)

        }
        .contentShape(Rectangle())
    }

    private var statusBand: some View {
        HStack(spacing: 8) {
            Image(systemName: statusBandIcon)
            Text(item.status.title)
                .fontWeight(.bold)
            Spacer(minLength: 8)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            statusBandColor,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }

    private var statusBandIcon: String {
        switch item.status {
        case .waiting: "exclamationmark.circle.fill"
        case .answered: "checkmark.circle.fill"
        case .closed: "lock.circle.fill"
        }
    }

    private var statusBandColor: Color {
        switch item.status {
        case .waiting: Color(red: 0.78, green: 0.16, blue: 0.14)
        case .answered: Color(red: 0.08, green: 0.52, blue: 0.32)
        case .closed: AppTheme.muted
        }
    }

    private var latestMessage: ConsultationMessage? {
        item.messages.last { $0.role != .system }
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
