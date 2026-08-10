import SwiftUI

struct AdminUserCard: View {
    let user: AdminUser
    let currentUserID: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSetActive: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    roleIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                        Text("@\(user.username) · \(user.agencyName ?? user.role.title)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(user.active ? "Active" : "Inactive")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(user.active ? AppTheme.brand : AppTheme.muted)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.vertical, 12)

                HStack {
                    Label(user.role.title, systemImage: "person.text.rectangle")
                    Spacer()
                    Text(user.activitySummary)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.muted)

                if user.id == currentUserID {
                    Text("This is your account. Manage personal details from Profile.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                } else {
                    HStack(spacing: 10) {
                        Button(user.active ? "Deactivate" : "Reactivate") {
                            onSetActive(!user.active)
                        }
                        .buttonStyle(.bordered)
                        .tint(user.active ? AppTheme.accent : AppTheme.brand)

                        if !user.active {
                            Button("Delete", role: .destructive, action: onDelete)
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 10)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var roleIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppTheme.brand)
            .frame(width: 38, height: 38)
            .background(AppTheme.brand.opacity(0.12), in: Circle())
    }

    private var iconName: String {
        switch user.role {
        case .doctor: "stethoscope"
        case .agent: "person.crop.rectangle.stack"
        case .admin: "gearshape.2"
        }
    }
}
