import AppKit
import Sparkle
import XCore

/// Updates through Sparkle, as Blit, Rune and Cue are updated: a published copy checks
/// https://x.banast.as/appcast.xml once a day and installs updates signed with the family's
/// EdDSA key (SUPublicEDKey) when the person says so. X › Check for Updates… checks now.
/// Debug builds and copies built from source (no SUFeedURL) never start the updater.
@MainActor
final class Updates {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        #if DEBUG
        controller = nil
        #else
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        controller = UpdatePolicy.runsUpdater(bundlePath: bundle.bundleURL.path, feedURL: feed,
                                              homeDirectory: NSHomeDirectory())
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        #endif
    }

    var isAvailable: Bool { controller != nil }
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
    func checkNow() { controller?.checkForUpdates(nil) }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
