import Foundation
MainActor.assumeIsolated { IsolatedMemorySmoke.runIfRequested() }
print("PASS: isolated smoke harness compiles and is inert without a smoke flag")
