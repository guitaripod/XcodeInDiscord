//
//  AppDelegate.swift
//  DiscordX
//
//  Created by Asad Azam on 28/9/20.
//  Copyright © 2021 Asad Azam. All rights reserved.
//

import Cocoa
import SwordRPC
import SwiftUI

final class AppViewModel: ObservableObject {
    @Published var showPopover = false
}

enum RefreshConfigurable: Int {
    case strict = 0
    case flaunt

    var message: String {
        switch self {
        case .strict:
            return "Timer will only keep the time you were active on Xcode"
        case .flaunt:
            return "Timer will not stop on Sleep and Wakeup of MacOS"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var timer: Timer?
    var rpc: SwordRPC?
    var startDate: Date?
    var inactiveDate: Date?
    var lastWindow: String?
    var notifCenter = NSWorkspace.shared.notificationCenter

    var statusItem: NSStatusItem!

    var isRelaunch: Bool = false

    func beginTimer() {
        timer = Timer(timeInterval: TimeInterval(refreshInterval), repeats: true) { [unowned self] _ in
            updateStatus()
        }

        RunLoop.main.add(timer!, forMode: .common)
        timer!.fire()
    }

    func clearTimer() {
        timer?.invalidate()
    }

    func updateStatus() {
        var presence = RichPresence()

        let applicationName = getActiveWindow()
        let fileName = getActiveFilename()
        let workspace = getActiveWorkspace()

        // determine file type
        if fileName != nil && applicationName == "Xcode" {
            presence.details = "Editing \(fileName!)"
            if let fileExt = getFileExt(fileName!), discordRPImageKeys.contains(fileExt) {
                presence.assets.largeImage = fileExt
                presence.assets.smallImage = discordRPImageKeyXcode
            } else {
                presence.assets.largeImage = discordRPImageKeyDefault
            }
        } else {
            if let appName = applicationName, xcodeWindowNames.contains(appName) {
                presence.details = "Using \(appName)"
                presence.assets.largeImage = appName.replacingOccurrences(
                    of: "\\s",
                    with: "",
                    options: .regularExpression
                ).lowercased()
                presence.assets.smallImage = discordRPImageKeyXcode
            }
        }

        presence.assets.smallImage = discordRPImageKeyXcode
        presence.assets.largeImage = discordRPImageKeyDefault
        presence.state = "Working on \(withoutFileExt((lastWindow ?? workspace) ?? "?" ))"

        // Xcode was just launched?
        if fileName == nil && workspace == nil {
            presence.assets.largeImage = discordRPImageKeyXcode
            presence.details = "No file open"
        }

        presence.timestamps.start = startDate!
        presence.timestamps.end = nil
        rpc!.setPresence(presence)
    }

    func initRPC() {
        // init discord stuff
        rpc = SwordRPC.init(appId: discordClientId)
        rpc!.delegate = self
        _ = rpc!.connect()
    }

    func deinitRPC() {
        rpc!.setPresence(RichPresence())
        rpc!.disconnect()
        rpc = nil
    }

    struct ContentView: View {
        @State var refreshConfigurable: RefreshConfigurable
        var appDelegate: AppDelegate

        init(_ appDelegate: AppDelegate) {
            self.appDelegate = appDelegate
            if isStrictModeEnabled {
                refreshConfigurable = .strict
            } else if isFlauntModeEnabled {
                refreshConfigurable = .flaunt
            } else {
                fatalError("Unspecified refresh type")
            }
        }

        var body: some View {
            VStack {

                Button("Start DiscordX") {
                    if appDelegate.rpc == nil {
                        appDelegate.isRelaunch = true
                        appDelegate.launchApplication()
                    } else {
                        print("DiscordX is already running")
                    }
                }

                Button("Stop DiscordX") {
                    if let rpc = appDelegate.rpc {
                        rpc.setPresence(RichPresence())
                        rpc.disconnect()
                        appDelegate.rpc = nil
                        appDelegate.clearTimer()
                    } else {
                        print("DiscordX is not running")
                    }
                }

                Picker("Mode:", selection: $refreshConfigurable) {
                    Text("Strict")
                        .help(RefreshConfigurable.strict.message)
                        .tag(RefreshConfigurable.strict)
                    Text("Flaunt")
                        .help(RefreshConfigurable.flaunt.message)
                        .tag(RefreshConfigurable.flaunt)
                }
                .pickerStyle(.radioGroup)

                Button("Quit DiscordX") {
                    exit(-1)
                }
                .foregroundColor(.red)
            }
            .onChange(of: refreshConfigurable) { newValue in
                switch newValue {
                case .strict:
                    isStrictModeEnabled = true
                    isFlauntModeEnabled = false
                case .flaunt:
                    isStrictModeEnabled = false
                    isFlauntModeEnabled = true
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        launchApplication()

        let contentView = ContentView(self)
        let view = NSHostingView(rootView: contentView)
        print(isStrictModeEnabled, isFlauntModeEnabled)

        view.frame = NSRect(x: 0, y: 0, width: 200, height: 160)

        let menuItem = NSMenuItem()
        menuItem.view = view

        let menu = NSMenu()
        menu.addItem(menuItem)

        // StatusItem is stored as a class property.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = menu
        let image = NSImage(named: "AppIcon")
        image?.size = NSSize(width: 24.0, height: 24.0)
        statusItem.button!.image = image
        statusItem.isVisible = true

        if let window = NSApplication.shared.windows.first {
            window.close()
        }
    }

    private lazy var addAllObservers: () = {
        // run on Xcode launch
        notifCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil,
            using: { [unowned self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if app.bundleIdentifier == xcodeBundleId {
                        initRPC()
                    }
                }
            }
        )

        // run on Xcode close
        notifCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil,
            using: { [unowned self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if app.bundleIdentifier == xcodeBundleId {
                        deinitRPC()
                    }
                }
            }
        )

        if isStrictModeEnabled {
            notifCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil,
                using: { [unowned self] notif in
                    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        if app.bundleIdentifier == xcodeBundleId {
                            // Xcode became active again (Frontmost)
                            if !isRelaunch {
                                if let inactiveDate = inactiveDate {
                                    let newDate: Date? = startDate?.addingTimeInterval(-inactiveDate.timeIntervalSinceNow)
                                    startDate = newDate
                                }
                            } else {
                                startDate = Date()
                                inactiveDate = nil
                                isRelaunch = false
                            }
                            // User can now start or stop DiscordX have to check if rpc is connected
                            if rpc != nil {
                                updateStatus()
                            }
                        }
                    }
                }
            )

            notifCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: nil,
                using: { [unowned self] notif in
                    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        if app.bundleIdentifier == xcodeBundleId {
                            // Xcode is inactive (Not frontmost)
                            inactiveDate = Date()
                            if rpc != nil {
                                updateStatus()
                            }
                        }
                    }
                }
            )
        }

        if !isFlauntModeEnabled {
            notifCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil,
                using: { [unowned self] notif in
                    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        if app.bundleIdentifier == xcodeBundleId {
                            // Xcode is going to become inactive (Sleep)
                            inactiveDate = Date()
                            if rpc != nil {
                                updateStatus()
                            }
                        }
                    }
                }
            )

            notifCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil,
                using: { [unowned self] notif in
                    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        if app.bundleIdentifier == xcodeBundleId {
                            // Xcode woke up from sleep
                            if let inactiveDate = inactiveDate {
                                let newDate: Date? = startDate?.addingTimeInterval(-inactiveDate.timeIntervalSinceNow)
                                startDate = newDate
                            }
                            if rpc != nil {
                                updateStatus()
                            }
                        }
                    }
                }
            )
        }
    }()

    func launchApplication() {

        for app in NSWorkspace.shared.runningApplications {
            // check if xcode is running
            if app.bundleIdentifier == xcodeBundleId {
                initRPC()
            }
        }

        _ = addAllObservers

    }

    func applicationWillTerminate(_ aNotification: Notification) {
        deinitRPC()
        clearTimer()
    }
}

extension AppDelegate: SwordRPCDelegate {
    func swordRPCDidConnect(_ rpc: SwordRPC) {
        startDate = Date()
        beginTimer()
    }

    func swordRPCDidDisconnect(_ rpc: SwordRPC, code: Int?, message msg: String?) {
        clearTimer()
    }

    func swordRPCDidReceiveError(_ rpc: SwordRPC, code: Int, message msg: String) {

    }
}
