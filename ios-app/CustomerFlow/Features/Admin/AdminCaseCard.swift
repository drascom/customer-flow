import SwiftUI

struct AdminCaseCard: View {
    let item: AdminCase
    let doctors: [AdminUser]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAssign: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.patientName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        statusChip
                    }

                    HStack(spacing: 6) {
                        Text(item.reference)
                        Text("•")
                        Text(item.uploadedAt, style: .relative)
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.muted)

                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                        Text(item.agencyName ?? "No agency")
                        Text("•")
                        Text(item.agentName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.vertical, 12)

                HStack(spacing: 8) {
                    metric(title: "Grafts", value: item.grafts)
                    metric(title: "Price", value: "\(item.currency) \(item.price)")
                    metric(title: "Media", value: "\(item.photoCount) · \(item.messageCount)")
                }

                Menu {
                    Button("Unassigned") { onAssign(nil) }
                    Divider()
                    ForEach(doctors) { doctor in
                        Button {
                            onAssign(doctor.id)
                        } label: {
                            if doctor.id == item.doctorID {
                                Label(doctor.displayName, systemImage: "checkmark")
                            } else {
                                Text(doctor.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stethoscope")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Assigned doctor")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Text(item.doctorName ?? "Unassigned")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(AppTheme.brand)
                    }
                    .padding(11)
                    .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var statusChip: some View {
        Text(shortStatus)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.13), in: Capsule())
    }

    private var shortStatus: String {
        switch item.status {
        case .waiting: "Waiting"
        case .answered: "Answered"
        case .closed: "Closed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .waiting: AppTheme.accent
        case .answered: AppTheme.brand
        case .closed: AppTheme.muted
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
