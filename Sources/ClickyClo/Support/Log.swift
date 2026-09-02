//
//  Log.swift
//  ClickyClo
//
//  Central, category-scoped logging. Uses os.Logger so output is visible in
//  Console.app and `log stream --predicate 'subsystem == "com.clickyclo.companion"'`
//  without shipping print() statements in a release build.
//

import Foundation
import os

enum Log {

    /// Kept in sync with `CFBundleIdentifier` in `Resources/Info.plist`. When the
    /// binary is run straight out of `.build/` there is no bundle identifier, so we
    /// fall back to the same literal rather than logging under an empty subsystem.
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.clickyclo.companion"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let geometry = Logger(subsystem: subsystem, category: "geometry")
}
