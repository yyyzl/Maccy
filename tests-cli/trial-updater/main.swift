import Foundation
let updater = SoftwareUpdater()
precondition(!updater.automaticallyChecksForUpdates)
updater.checkForUpdates()
print("PASS: isolated trial updater compiles without Sparkle and performs no update")
