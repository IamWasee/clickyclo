//
//  main.swift
//  ClickyClo
//
//  Manual `NSApplication` bootstrap. ClickyClo has no storyboard, no main menu,
//  and no window of its own beyond the overlay, so the standard nib-driven
//  `NSApplicationMain` entry point would only get in the way.
//

import AppKit

// `.accessory` keeps ClickyClo out of the Dock and out of the Cmd-Tab switcher,
// and — importantly for a guidance overlay — stops it from ever stealing focus
// from the app the user is working in. Set before `run()` so the app never
// flashes into the Dock at launch.
let application = NSApplication.shared
if !application.setActivationPolicy(.accessory) {
    Log.app.error("Failed to enter accessory activation policy; ClickyClo may appear in the Dock")
}

// Held for the process lifetime: `NSApplication.delegate` is a weak reference.
let appDelegate = AppDelegate()
application.delegate = appDelegate

application.run()
