# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

InstantSpaceSwitcher is a macOS menu bar app that eliminates the space-switching animation by posting synthetic trackpad gestures with artificially high velocity. It does **not** require SIP to be disabled. The project targets macOS 13+.

## Build commands

```sh
# Standard build (universal binary, release)
./dist/build.sh

# Debug build
./dist/build.sh --debug

# Clean build
./dist/build.sh --clean

# Run tests
swift test

# Run a single test
swift test --filter OverlayDetectionTests/testAppExposeDetected

# Lint
swiftlint
```

The build script compiles arm64 and x86_64 in parallel, lipo-merges them, bundles `InstantSpaceSwitcher.app` under `build/`, and ad-hoc signs it. The app is not notarized (not signed with a paid Apple Developer account).

## Architecture

### Targets

- **`ISS`** — Pure C library (`Sources/ISS/ISS.c`, `Sources/ISS/include/ISS.h`). Links `ApplicationServices`, `CoreFoundation`, `IOKit`. Contains all space-switching logic and the CGEvent tap. No Swift.
- **`InstantSpaceSwitcher`** — Swift macOS app (`Sources/InstantSpaceSwitcher/`). Depends on `ISS`. No Xcode project file; uses SPM + `Info.plist` at root.
- **`ISSCli`** — Thin C CLI wrapper (`Sources/ISSCli/main.c`). Accepts `left`, `right`, `index <n>` arguments. Bundled inside the `.app` at `Contents/MacOS/ISSCli`.
- **`ISSTests`** — XCTest target for the C library's Exposé/Mission Control detection functions.

### How switching works

`ISS.c` posts three `kCGSEventDockControl` events (began/changed/ended) with `kIOHIDEventTypeDockSwipe` HID type and a velocity high enough that the animation is skipped. The key insight is using `±FLT_TRUE_MIN` as the progress value — this makes the switch instant.

For keyboard hotkeys (`iss_switch`, `iss_switch_to_index`) the app calls the C library directly. For trackpad swipe override (`iss_set_swipe_override(true)`), a `CGEventTap` at `kCGHeadInsertEventTap` intercepts real dock-swipe events from the kernel (sourcePid == 0), suppresses them, and fires its own instant switch instead.

Space bounds are tracked via a **predictions dictionary** (displayID → predicted index) because CGS APIs may not reflect the new space immediately after posting the gesture. `iss_reset_predictions()` is called on `activeSpaceDidChangeNotification`.

### Swift app structure

```
Core/
  App.swift                    — NSApplicationMain entry point
  AppDelegate.swift            — Wires everything together; owns HotkeyStore, MenuBarController
  Constants.swift              — App name and other constants
  MenuBarController.swift      — NSStatusItem, menu construction, space indicator rendering
  MenuBarIconRenderer.swift    — Renders space indicator image

Hotkeys/
  HotkeyConfiguration.swift   — HotkeyCombination (Codable), HotkeyIdentifier enum, HotkeyStore (ObservableObject)
  HotKeyManager.swift          — Carbon RegisterEventHotKey wrapper
  HotkeyRecorder.swift         — Records new hotkeys from NSEvent
  GlobalEventTapRecorder.swift — Alternative recorder using the event tap

UI/
  PreferencesWindowController.swift  — Opens/presents the panel
  PreferencesPanel.swift             — NSPanel subclass (canBecomeKey/Main)
  PreferencesTabViewController.swift — Tab layout
  GeneralSettingsViewController.swift
  KeyboardShortcutsViewController.swift
  HotkeyPreferencesView.swift        — SwiftUI view listing all hotkeys
  FormView.swift                     — Reusable form row layout
  ShortcutRecorderControl.swift      — NSView for capturing a shortcut
  OSDWindow.swift                    — Floating on-screen display (shows space number)
```

`HotkeyStore` is `@Published`-driven; `AppDelegate` subscribes via Combine and re-registers Carbon hotkeys whenever the store changes.

### Exposé / Mission Control detection

`iss_is_expose_active()` / `iss_is_mission_control_active()` scan `CGWindowListCopyWindowInfo` for Dock windows at layer 18 and 20. App Exposé: layer-18 present AND `count(layer=20) <= count(layer-18)`. Mission Control: layer-18 present AND `count(layer=20) > count(layer-18)`. These heuristics are empirical and tested in `ISSTests/ExposeMcDetectTests.swift` with hardcoded window-list fixtures from real macOS probes.

### UserDefaults keys

| Key | Type | Default |
|---|---|---|
| `swipeOverride` | Bool | false |
| `gestureSpeed` | Double | 2000.0 |
| `overlayDetectionEnabled` | Bool | true |
| `hotkey.<identifier>` | JSON-encoded `HotkeyCombination` | see `HotkeyCombination` defaults |
| `enabled.<identifier>` | Bool | true |

### Personal modifications (this branch only)

Two additions on top of upstream, not present on `main` or `feature/hide-menu-bar-icon`:

**Hide menu bar icon** — `GeneralSettingsViewController`, `MenuBarController`, `AppDelegate`
- UserDefaults key: `hideMenuBarIcon` (Bool, default false)
- Checkbox in the System section of General settings
- Toggles `statusItem.isVisible` via `MenuBarController.setIconVisible(_:)`
- Applied on launch in `AppDelegate.applicationDidFinishLaunching`
- To recover when hidden: relaunch the app (triggers `handleReopen` → opens Settings)
- Submitted upstream as PR #73

**Wrap-around spaces** — `AppDelegate`, `GeneralSettingsViewController`
- UserDefaults key: `wrapAroundSpaces` (Bool, default false)
- Checkbox in the System section of General settings
- Logic lives in `AppDelegate.performSpaceSwitch(_:)` — when at the leftmost/rightmost space and wrap is enabled, calls `iss_switch_to_index` to jump to the opposite end instead of beeping
- Ported from upstream PR #33 (`https://github.com/jurplel/InstantSpaceSwitcher/pull/33`)
- If upstream merges PR #33, remove this from `personal` and pull from `main`

### SwiftLint

Disabled rules: `trailing_whitespace`, `identifier_name`, `type_name`, `nesting`. Opt-in: `explicit_enum_raw_value`. Line length warning at 140, error at 180.
