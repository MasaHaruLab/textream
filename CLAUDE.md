# textream (personal fork)

Fork of f/textream (macOS teleprompter, no upstream LICENSE — personal use only, do not redistribute builds).

## Our mod
- `seeThroughNoBlur` setting ("See-through (no blur)" toggle in Settings): skips the NSVisualEffectView blur in both notch-transparency and floating-glass backgrounds, leaving only the adjustable black tint — screen content behind stays crisp.
- Floating window free-resize: min 200×40, max = screen; frame autosaved ("FloatingPrompterPanel"). Below 90pt tall = compact mode (control bar/elapsed time hidden, one-line prompter). Word-tracking scroll uses a critically damped spring. Her `overlayMode` is set to `floating` (was default pinned).
- Matching rewrites (stall fixes) are chronicled in 项目日志.md; debug log toggle: `defaults write dev.fka.textream matchDebugLog -bool YES` → ~/Library/Logs/Textream-match.log (currently ON — turn off once stable).

## Build (no Xcode installed — swiftc manual build)
```
mkdir -p build/src && cp Textream/Textream/*.swift build/src/
sed -i '' '/^#Preview {$/,$d' build/src/ContentView.swift   # strip Xcode-only #Preview macro
cd build/src && xcrun swiftc -O -parse-as-library -swift-version 5 -module-name Textream \
  -target arm64-apple-macosx15.7 *.swift -o ../Textream.bin
```
Then: copy /Applications/Textream.app as donor bundle → swap Contents/MacOS/Textream with the new binary → `codesign --force --deep -s -` → replace /Applications/Textream.app.

## Rollback
`brew reinstall --cask f/textream/textream` restores official v1.6.2.

## Notes
- Patch base = tag v1.6.2 (must match installed donor bundle version).
- App hides its window when launched from terminal (`launchedExternally` → accessory mode); a second `open -a Textream` surfaces it.
- Settings live in `defaults` domain `dev.fka.textream` (not sandboxed). speechLocale=zh-CN, hideFromScreenShare defaults true.
