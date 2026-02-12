import SwiftUI

@main
struct PanteraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate for Menu Bar & Lifecycle Management

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    // Core Managers
    var audioManager = AudioDeviceManager()
    var appMonitor = AppAudioMonitor()
    var mediaManager = MediaRemoteManager()
    var keyboardManager = KeyboardShortcutManager()
    
    // UI Components
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var detachedWindow: NSPanel?
    
    // Event Monitor for closing popover
    private var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Setup UI
        setupMenuBar()
        setupPopover()
        
        // Setup Keyboard Callbacks
        setupKeyboardCallbacks()
        
        // Setup Observers
        setupObservers()
    }
    
    private func setupObservers() {
        UserDefaults.standard.addObserver(self, forKeyPath: "stayOpen", options: [.new], context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "stayOpen" {
            updatePopoverBehavior()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    func updatePopoverBehavior() {
        let stayOpen = UserDefaults.standard.bool(forKey: "stayOpen")
        
        if stayOpen {
            // Switch to detached window mode
            if popover.isShown {
                popover.performClose(nil)
            }
            
            if detachedWindow == nil {
                createDetachedWindow()
            }
            
            showDetachedWindow()
        } else {
            // Switch back to popover mode
            if let window = detachedWindow {
                window.close()
                detachedWindow = nil
            }
            // Popover behavior is always transient for standard mode
            popover.behavior = .transient
        }
    }

    private func createDetachedWindow() {
        let contentView = ContentView()
            .environmentObject(audioManager)
            .environmentObject(appMonitor)
            .environmentObject(mediaManager)
            
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
            
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        
        window.contentViewController = NSHostingController(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("PanteraMainWindow")
        
        detachedWindow = window
    }
    
    private func showDetachedWindow() {
        guard let window = detachedWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - UI Setup
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Pantera")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }
    
    private func setupPopover() {
        let contentView = ContentView()
            .environmentObject(audioManager)
            .environmentObject(appMonitor)
            .environmentObject(mediaManager)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 600) // Adjusted height constraint
        popover.behavior = .transient // Default behavior, will be overridden by our event monitor logic if needed
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Ensure popover can become key to handle input if needed
        popover.animates = true
    }
    
    // MARK: - Event Monitoring
    
    private func startEventMonitor() {
        // Stop any existing monitor
        stopEventMonitor()
        
        // Monitor for clicks outside the popover to close it
        // We only start this if "Stay Open" is FALSE.
        // If "Stay Open" is TRUE, we don't monitor outside clicks (or we handle them differently).
        // Actually, .transient behavior handles closing on outside clicks automatically.
        // But to implement "Stay Open", we might need to switch behavior or manage closing manually.
        
        // Strategy:
        // Use .applicationDefined behavior for "Stay Open"
        // Use .transient behavior for standard mode
    }
    
    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - Popover Management
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if UserDefaults.standard.bool(forKey: "stayOpen") {
            if detachedWindow == nil {
                createDetachedWindow()
            }
            
            if let window = detachedWindow, window.isVisible {
                window.close() // Or maybe minimize? But close toggles visibility
            } else {
                showDetachedWindow()
            }
        } else {
            if popover.isShown {
                closePopover(sender)
            } else {
                showPopover(sender)
            }
        }
    }
    
    func showPopover(_ sender: AnyObject?) {
        if UserDefaults.standard.bool(forKey: "stayOpen") {
            showDetachedWindow()
            return
        }
        
        guard let button = statusBarItem.button else { return }
        
        // Update behavior based on settings before showing
        updatePopoverBehavior()
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }
    
    // MARK: - Keyboard Callbacks
    
    private func setupKeyboardCallbacks() {
        keyboardManager.onToggleMute = { [weak self] in
            self?.audioManager.toggleMute()
        }
        
        keyboardManager.onVolumeUp = { [weak self] in
            guard let manager = self?.audioManager else { return }
            manager.setSystemVolume(min(1.0, manager.systemVolume + 0.1))
        }
        
        keyboardManager.onVolumeDown = { [weak self] in
            guard let manager = self?.audioManager else { return }
            manager.setSystemVolume(max(0, manager.systemVolume - 0.1))
        }
        
        keyboardManager.onPlayPause = { [weak self] in
            self?.mediaManager.togglePlayPause()
        }
        
        keyboardManager.onNextTrack = { [weak self] in
            self?.mediaManager.nextTrack()
        }
        
        keyboardManager.onPreviousTrack = { [weak self] in
            self?.mediaManager.previousTrack()
        }
    }
}
