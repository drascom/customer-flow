import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    let notifications: [AppNotification]
    let unreadCount: Int
    let onMarkAllRead: () async -> Void
    let onSelect: (AppNotification) async -> Void

    var body: some View {
        NavigationStack {
            Group {
                if notifications.isEmpty {
                    ContentUnavailableView(
                        String(localized: "notifications.empty.title", defaultValue: "No notifications"),
                        systemImage: "bell.slash",
                        description: Text(String(
                            localized: "notifications.empty.message",
                            defaultValue: "New case activity will appear here."
                        ))
                    )
                } else {
                    List(notifications) { item in
                        Button {
                            dismiss()
                            Task { await onSelect(item) }
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Circle()
                                    .fill(item.readAt == nil ? AppTheme.brand : Color.clear)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 7)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(item.body)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                        .lineLimit(3)
                                    HStack {
                                        Text(item.caseReference ?? "Customer Flow")
                                        Spacer()
                                        Text(item.createdAt, style: .relative)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.muted)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(item.readAt == nil ? AppTheme.brand.opacity(0.08) : AppTheme.surfaceStrong)
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "notifications.title", defaultValue: "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if unreadCount > 0 {
                        Button(String(localized: "notifications.mark_all", defaultValue: "Mark all read")) {
                            Task { await onMarkAllRead() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "notifications.close", defaultValue: "Close notifications"))
                }
            }
        }
    }
}
