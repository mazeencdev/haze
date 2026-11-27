import SwiftUI
import AppKit

@main
struct HazeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: CalendarStore
    @StateObject private var app: AppModel

    init() {
        let s = CalendarStore()
        _store = StateObject(wrappedValue: s)
        _app = StateObject(wrappedValue: AppModel(store: s))
    }

    var body: some Scene {
        Window("Haze", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(app)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
        .commands { HazeCommands(app: app, store: store) }

        MenuBarExtra {
            MenuBarAgenda()
                .environmentObject(store)
                .environmentObject(app)
                .environment(\.colorScheme, .light)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct HazeCommands: Commands {
    @ObservedObject var app: AppModel
    @ObservedObject var store: CalendarStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Event") { app.newEvent() }.keyboardShortcut("n")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Edit Event") { if let e = app.selectedEvent { app.edit(e) } }
                .keyboardShortcut("e")
                .disabled(app.selectedEvent?.editable != true)
            Button("Delete Event") { if let e = app.selectedEvent { app.deleteWithUndo(e) } }
                .keyboardShortcut(.delete)
                .disabled(app.selectedEvent?.editable != true)
        }
        CommandMenu("Go") {
            Button("Today") { app.goToday() }.keyboardShortcut("t")
            Button("Previous") { app.shift(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next") { app.shift(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Divider()
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                Button(p.title) { app.setPage(p) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
            Divider()
            Button("Sync Now") { store.refreshRemote() }.keyboardShortcut("r")
        }
    }
}
