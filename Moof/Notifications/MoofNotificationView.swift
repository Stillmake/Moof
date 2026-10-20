import SwiftUI

struct MoofNotificationView: View {
    @ObservedObject var item: MoofNotificationItem

    private let center = MoofNotificationCenter.shared

    var body: some View {
        let close = { center.close(item.id) }
        let copy = { center.copy(item.id) }
        let action = item.notification.action == nil ? nil : { center.performAction(item.id) }
        Group {
            switch item.notification.theme {
            case .standard:
                MoofNotificationCard(notification: item.notification, dismissState: item.dismissState, close: close, copy: copy, action: action)
            case .eldenRing:
                EldenRingCard(notification: item.notification, dismissState: item.dismissState, isHovering: item.isHovering, close: close, copy: copy, action: action)
            case .mario:
                MarioCard(notification: item.notification, dismissState: item.dismissState, isHovering: item.isHovering, close: close, copy: copy, action: action)
            case .hollowKnight:
                HollowKnightCard(notification: item.notification, dismissState: item.dismissState, isHovering: item.isHovering, close: close, copy: copy, action: action)
            }
        }
        // Hover covers the transparent parts of a card too; the action runs only from its button.
        .contentShape(.rect)
        .onHover { center.setHovering(item.id, $0) }
        .padding(item.notification.theme == .standard ? MoofNotificationLayout.glassShadowMargin : 0)
    }
}
