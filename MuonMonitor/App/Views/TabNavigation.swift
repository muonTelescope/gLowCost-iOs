import SwiftUI
import UIKit

/// A reselect scrolls the visible page, preserving its navigation and edit state.
enum TabScrollTop {
    static let notification = Notification.Name("MuonTabReselected")
    static func anchor(_ tab: AppTab) -> String { "tab-top-" + tab.rawValue }
    static func request(_ tab: AppTab) { NotificationCenter.default.post(name: notification, object: tab) }
}

private struct TabScrollTopModifier: ViewModifier {
    let tab: AppTab
    @State private var visible = false
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { visible = true }
                .onDisappear { visible = false }
                .onReceive(NotificationCenter.default.publisher(for: TabScrollTop.notification)) { note in
                    guard visible, note.object as? AppTab == tab else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(TabScrollTop.anchor(tab), anchor: .top) }
                }
        }
    }
}

extension View {
    func tabScrollTop(_ tab: AppTab) -> some View { modifier(TabScrollTopModifier(tab: tab)) }
}

/// SwiftUI selection bindings don't report selecting an already-selected system
/// tab. Observe UIKit's public delegate callback, forwarding all other behavior.
struct SystemTabReselectObserver: UIViewControllerRepresentable {
    var reselected: () -> Void
    func makeUIViewController(context: Context) -> Observer { Observer() }
    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.reselected = reselected
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }
    static func dismantleUIViewController(_ controller: Observer, coordinator: ()) { controller.uninstall() }

    final class Observer: UIViewController, UITabBarControllerDelegate {
        var reselected: (() -> Void)?
        private weak var observed: UITabBarController?
        private weak var original: UITabBarControllerDelegate?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); install() }
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            func find(_ controller: UIViewController) -> UITabBarController? {
                if let tabs = controller as? UITabBarController { return tabs }
                return controller.children.lazy.compactMap { find($0) }.first
            }
            guard let tabs = find(root), tabs.delegate !== self else { return }
            uninstall(); observed = tabs; original = tabs.delegate; tabs.delegate = self
        }
        func uninstall() {
            if let observed, observed.delegate === self { observed.delegate = original }
            observed = nil; original = nil
        }
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            guard original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true else { return false }
            if tabBarController.selectedViewController === viewController {
                reselected?()
                return false // Scroll this page instead of popping its navigation stack.
            }
            return true
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
