import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import SophiaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var panel: NotchPanel!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var settingsWindow: NSWindow?
    private var standbyItem: NSMenuItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NotchPanel(model: controller.model) { [weak self] in self?.controller.escapePressed() }
        controller.panel = panel
        panel.orderFrontRegardless()

        for (key, action) in [(UInt32(kVK_Space), 0), (UInt32(kVK_ANSI_S), 0), (UInt32(kVK_ANSI_D), 1)] {
            if let hk = HotKey(keyCode: key, modifiers: UInt32(controlKey | optionKey), handler: { [weak self] in action == 0 ? self?.controller.hotkeyPressed() : self?.controller.dictationPressed() }) { hotKeys.append(hk) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sophia")
        let menu = NSMenu()
        menu.addItem(withTitle: "Talk to Sophia (⌃⌥S)", action: #selector(talk), keyEquivalent: "").target = self
        standbyItem = menu.addItem(withTitle: "Go off (until I wake her)", action: #selector(toggleStandby), keyEquivalent: "")
        standbyItem?.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sophia", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu

        AppSettings.shared.$standby.receive(on: DispatchQueue.main).sink { [weak self] off in MainActor.assumeIsolated {
            self?.standbyItem?.title = off ? "Wake Sophia" : "Go off (until I wake her)"
            self?.statusItem.button?.image = NSImage(systemSymbolName: off ? "waveform.slash" : "waveform", accessibilityDescription: off ? "Sophia is off" : "Sophia")
        } }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: .sophiaEntrance, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.previewEntrance() } }
        NotificationCenter.default.addObserver(forName: .sophiaTelegramChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.phone.start() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.panel.reposition(model: self?.controller.model) } }

        if UserDefaults.standard.object(forKey: "firstRunDone") == nil { UserDefaults.standard.set(true, forKey: "firstRunDone"); openSettings() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.controller.startBackground() }
    }

    @objc func talk() { controller.hotkeyPressed() }
    @objc func toggleStandby() { if AppSettings.shared.standby { controller.wakeFromStandby() } else { AppSettings.shared.standby = true } }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: AppSettings.shared, pairingCode: { [weak self] in self?.controller.phone.pairingCode ?? "" })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Sophia"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

if CommandLine.arguments.contains("--status") {
    print("Screen Recording: \(CGPreflightScreenCaptureAccess() ? "on" : "off")")
    print("Accessibility: \(AXIsProcessTrusted() ? "on" : "off")")
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
