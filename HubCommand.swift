import Foundation

/// A `goorgle://` URL sent by Yair's Apps, the menu bar hub.
///
/// URLs are used only for things the user just clicked, where launching Goorgle
/// if it isn't running is the wanted behaviour. Menu bar consolidation is
/// deliberately *not* one of them — see `HubMenuBar`.
enum HubCommand {
    static let scheme = "goorgle"

    /// `goorgle://search` — open the search panel.
    case search
    /// `goorgle://preferences` — open the preferences window.
    case preferences

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "search": self = .search
        case "preferences": self = .preferences
        default: return nil
        }
    }
}

/// The menu bar consolidation channel with Yair's Apps.
///
/// Distributed notifications rather than a `goorgle://` URL, deliberately. A
/// URL open goes through LaunchServices, which is a *launch* primitive: aimed
/// at Goorgle while it is still finishing its own launch, it can cause the
/// half-started instance to be replaced. Consolidation never wants to launch
/// anything, so it has no business going through the launcher.
///
/// Goorgle asks for the current state rather than waiting to be told, so
/// there's no window in which it has launched but the hub hasn't noticed yet.
///
/// The state rides in the notification *name*; `userInfo` on distributed
/// notifications doesn't cross a sandbox boundary reliably, and some apps in
/// this family are sandboxed.
enum HubMenuBar {
    static let hide = Notification.Name("com.matanlevi.YairsApps.menuBar.hide")
    static let show = Notification.Name("com.matanlevi.YairsApps.menuBar.show")
    static let query = Notification.Name("com.matanlevi.YairsApps.menuBar.query")

    /// Starts listening, then asks the hub what the current state is. If the hub
    /// isn't running nothing answers, and the icon simply stays visible.
    static func start(_ apply: @escaping (Bool) -> Void) {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: hide, object: nil, queue: .main) { _ in apply(false) }
        center.addObserver(forName: show, object: nil, queue: .main) { _ in apply(true) }
        center.postNotificationName(query, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
