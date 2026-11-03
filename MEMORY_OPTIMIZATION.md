# Maccy image-memory experiment

Based on upstream Maccy tag `2.6.1`. This is an experimental source change. ARM64 Debug apps have been built, but the optimized app has not been installed as a replacement.

## Changes

- Query universal-clipboard markers separately when loading history. The icon cache can use this hint instead of traversing every item's contents. A failed query or an ambiguous duplicate marker falls back to the original lookup.
- Generate thumbnails and previews using a short-lived `ModelContext` for saved, unchanged items. Unsaved or deleted items use the original context so edits are not read from a stale store.
- Render downsized images into independent bitmaps instead of a drawing closure that retains the source image. Release cached images when a history row disappears and allow them to be regenerated.
- The original clipboard content and storage schema are unchanged. This change does not migrate or delete data.

## Command-line validation

The scripts below use only synthetic data and the macOS Command Line Tools. They do not access the system clipboard or the user's Maccy database.

```sh
sh tests-cli/clipboard-metadata/run.sh
sh tests-cli/image-resize/run.sh
sh tests-cli/image-loader/run.sh
sh tests-cli/decorator/run.sh
sh tests-cli/swiftdata-load/run.sh
sh tests-cli/image-loader-benchmark/run.sh
sh tests-cli/smoke-compile/run.sh
```

The SwiftData tests use the actual system SwiftData runtime, with manually implemented synthetic models because the installed Command Line Tools lack the `SwiftDataMacros` plugin. The synthetic model has a child-to-parent relationship rather than Maccy's exact inverse to-many relationship. The decorator test uses test doubles for the third-party `Defaults` and `Sauce` modules.

An example run with 10 synthetic image payloads totaling 40 MiB measured approximately 45 MiB for the legacy all-content scan and 5 MiB for the marker-only lookup. Separate rendered-thumbnail runs measured approximately 21–32 MiB before and 15–17 MiB after; before rendering, eager rasterization can instead use more memory. Numbers fluctuate with macOS memory compression and do not establish the memory usage of the full Maccy app.

## GitHub Actions

`.github/workflows/memory-optimization.yml` cross-compiles ARM64 optimized and baseline apps on GitHub's `macos-26-intel` runner. The baseline replaces the five optimized image/history source files with those from the upstream `2.6.1` commit, while keeping the same DEBUG-only synthetic harness and private-pasteboard injection. It verifies the executable architecture and runs isolated regression tests natively on Intel. Pushing a branch named `memory-optimization/...` triggers it; `workflow_dispatch` is also configured. Manual dispatch requires the workflow to exist on the repository's default branch. Only source and synthetic tests are involved; no clipboard database is included. The artifacts are unsigned and experimental, not replacements for the installed app.

The DEBUG-only smoke harness refuses to run unless the bundle identifier is `org.yyyzl.MaccyMemoryTest`, clipboard monitoring is disabled, and the store is not in-memory. It creates synthetic images only in that separate test container; the paste test uses a uniquely named private pasteboard, never the system clipboard.

## Full-app isolated comparison

On macOS 15.7.3, the ARM64 Debug baseline and optimized builds from [run 41658887111](https://github.com/yyyzl/Maccy/actions/runs/41658887111) were run sequentially against the same isolated synthetic store. It contained 10 TIFFs totaling 54.9 MiB and one PNG of 4.8 MiB. No user clipboard or history was used.

- Both apps generated all 10 thumbnails. After settling, physical footprints overlapped: baseline approximately 49–56 MB; optimized approximately 48–50 MB. This test does not demonstrate a large reduction in overall footprint.
- In two additional samples, `heap` reported 59.9 MiB of allocated CFData byte storage for the baseline and about 5.6 MiB for the optimized build. This is a different metric from physical footprint, and the two must not be added or equated.
- In those samples, peak physical footprint was 166–167 MB for the baseline and 171–173 MB for the optimized build. Peaks are workload-dependent; do not assume the patch reduces them.
- The actual `Clipboard.copy` implementation wrote both synthetic TIFF and PNG to a named private pasteboard, and both formats matched the stored data byte-for-byte. Pasting into another application with simulated keystrokes was not tested.

## Known limitations

- ARM64 Debug builds and isolated component tests passed on GitHub Actions, and the two built apps were run against a synthetic store locally. The original full test suite has not run. `xcodebuild`, `SwiftDataMacros`, and `FoundationMacros` are absent from the installed local Command Line Tools; SourceKit also reports unresolved project types and the `Defaults` module without the project build configuration.
- Clipboard restoration is unchanged: `Clipboard.copy` still uses the original context. Duplicate detection and parts of the preview UI can also traverse full content, so image data may still be retained after copying, pasting, or opening a preview. The patch does not yet establish a complete load-on-paste lifecycle.
- The private-pasteboard byte check does not test the system clipboard or pasting into a destination app. The memory effect with a real history and a Release build is unknown. Do not replace the installed Maccy based on this experiment.
