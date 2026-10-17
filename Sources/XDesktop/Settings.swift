import AppKit
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications
import XCore

/// Preferences that belong to the app rather than the page: the window's level and notifications.
@MainActor
@Observable
final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    /// Applies the window level; set by the app delegate.
    @ObservationIgnored var onKeepOnTop: ((Bool) -> Void)?

    var keepOnTop: Bool {
        didSet { defaults.set(keepOnTop, forKey: "keepOnTop"); onKeepOnTop?(keepOnTop) }
    }
    var notifyUnread: Bool {
        didSet { defaults.set(notifyUnread, forKey: "notifyUnread") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        keepOnTop = defaults.bool(forKey: "keepOnTop")
        notifyUnread = defaults.bool(forKey: "notifyUnread")
    }
}

/// Open at login, through the system's login items (System Settings › General › Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Posts a notification when X's unread count rises while the app is in the background. Only the
/// count in X's page title is used, never post content. Off unless the person turns it on.
@MainActor
final class UnreadNotifier {
    private var lastCount: Int?

    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    func update(badge: String?, enabled: Bool) {
        let count = badge.flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) } ?? 0
        defer { lastCount = count }
        guard enabled, Self.available, let lastCount, count > lastCount, !NSApp.isActive, let badge else { return }
        let content = UNMutableNotificationContent()
        content.title = "X"
        content.body = count == 1 ? "1 unread notification" : "\(badge) unread notifications"
        // One identifier, so a newer count replaces the older notification instead of stacking.
        let request = UNNotificationRequest(identifier: "unread", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    static func requestPermission() async -> Bool {
        guard available else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let model: BrowserModel
    private let preferences: AppPreferences
    private let updates: Updates

    init(model: BrowserModel, preferences: AppPreferences, updates: Updates) {
        self.model = model; self.preferences = preferences; self.updates = updates
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, preferences: preferences, updates: updates))
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let model: BrowserModel
    @Bindable var preferences: AppPreferences
    let updates: Updates
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?
    @State private var notificationNote: String?
    @State private var checksForUpdates = false

    var body: some View {
        Form {
            Section("Refresh") {
                Toggle("Refresh the feed automatically", isOn: Binding(get: { model.autoRefresh },
                                                                      set: { if $0 != model.autoRefresh { model.toggleAutomatic() } }))
                Picker("Refresh every", selection: Binding(get: { model.refreshInterval }, set: model.setRefreshInterval)) {
                    ForEach(RefreshInterval.choices, id: \.self) { Text(RefreshInterval.name($0)).tag($0) }
                }
                .disabled(!model.autoRefresh)
                Toggle("Keep my place when the feed refreshes", isOn: Binding(get: { model.keepsPlace },
                                                                             set: { if $0 != model.keepsPlace { model.toggleKeepsPlace() } }))
                Toggle("Show Recent when Following opens", isOn: Binding(get: { model.followingRecent },
                                                                        set: { if $0 != model.followingRecent { model.toggleFollowingRecent() } }))
            }
            Section("Window") {
                Toggle("Keep the window above other apps", isOn: $preferences.keepOnTop)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setLogin(enabled) }
                if let loginNote {
                    Text(loginNote).font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section {
                Toggle("Notify me when unread notifications increase", isOn: $preferences.notifyUnread)
                    .disabled(!UnreadNotifier.available)
                    .onChange(of: preferences.notifyUnread) { _, enabled in if enabled { askForNotifications() } }
                if let notificationNote { Text(notificationNote).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Uses only the count X shows in its page title, while X is in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if updates.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $checksForUpdates)
                        .onChange(of: checksForUpdates) { _, value in updates.checksAutomatically = value }
                    Button("Check Now") { updates.checkNow() }.disabled(!updates.canCheck)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            checksForUpdates = updates.checksAutomatically
            openAtLogin = LoginItem.isEnabled
            if LoginItem.needsApproval { loginNote = "Allow X in System Settings to finish turning this on." }
        }
    }

    private func setLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { loginNote = nil; return }
        do {
            try LoginItem.set(enabled)
            loginNote = LoginItem.needsApproval ? "Allow X in System Settings to finish turning this on." : nil
        } catch {
            loginNote = "macOS didn't change the login item: \(error.localizedDescription)"
            openAtLogin = LoginItem.isEnabled
        }
    }

    private func askForNotifications() {
        Task {
            if await UnreadNotifier.requestPermission() {
                notificationNote = nil
            } else {
                preferences.notifyUnread = false
                notificationNote = "Allow notifications for X in System Settings › Notifications, then turn this on again."
            }
        }
    }
}
