import Foundation

extension UserRole {
    var appTourSteps: [AppTourStep] {
        switch self {
        case .doctor:
            [
                AppTourStep(
                    id: 0,
                    icon: "magnifyingglass",
                    title: "Find the next case",
                    message: "Search by patient or reference, choose My Waiting or Unassigned, and switch between oldest and newest cases.",
                    tapHint: "Tap a case card to open the consultation."
                ),
                AppTourStep(
                    id: 1,
                    icon: "photo.on.rectangle.angled",
                    title: "Review every photo",
                    message: "Swipe left or right inside the post. Tap the image for full screen, then use drawing or text to mark clinical areas.",
                    tapHint: "Tap the large photo; use the side arrows or swipe."
                ),
                AppTourStep(
                    id: 2,
                    icon: "square.and.pencil",
                    title: "Send your recommendation",
                    message: "The response area is already open at the bottom. Add your note, approximate graft number and recommended price.",
                    tapHint: "Scroll to Doctor Response, then tap Send response."
                ),
                AppTourStep(
                    id: 3,
                    icon: "arrow.triangle.branch",
                    title: "The patient stays with you",
                    message: "Your first accepted response assigns the patient to you unless an admin assigned them earlier. New updates return to your waiting queue.",
                    tapHint: "Use My Waiting for returning patient updates."
                ),
            ]
        case .agent:
            [
                AppTourStep(
                    id: 0,
                    icon: "tray.full",
                    title: "Manage your cases",
                    message: "Search and filter your own cases by status. Each card shows the latest state and opens the editable case screen.",
                    tapHint: "Tap a case card to review or update it."
                ),
                AppTourStep(
                    id: 1,
                    icon: "plus.circle",
                    title: "Create a consultation",
                    message: "The guided flow checks the patient first, then asks for the note, estimated graft and price, and finally the photo set.",
                    tapHint: "Tap + New beside the filter to start."
                ),
                AppTourStep(
                    id: 2,
                    icon: "bubble.left.and.bubble.right",
                    title: "Continue the conversation",
                    message: "Doctor recommendations appear below the photos. Adding a new message or photo automatically sends the case back to Waiting for Doctor.",
                    tapHint: "Open the case and use Add update below the thread."
                ),
                AppTourStep(
                    id: 3,
                    icon: "checkmark.circle",
                    title: "Close only when complete",
                    message: "After the doctor answers, confirm that the consultation is complete. Only the agent can close the case.",
                    tapHint: "Tap Confirm & Close after reviewing the response."
                ),
            ]
        case .admin:
            []
        }
    }
}
