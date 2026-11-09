# GestaltReset

Simple iOS utility that uses [worse_query](https://github.com/forcequitOS/worse_query) (by forcequitOS / Taj C) to reach the SystemGroup path that holds the MobileGestalt cache and allows you to:

- Backup the current `com.apple.MobileGestalt.plist`
- Delete that plist
- Clear related caches under the same SystemGroup

This is the same file that **GestaltX** (and similar MobileGestalt editors) read and write.

## Requirements

- iOS 26.0 – 26.7.2 / 27.x (same range as worse_query)
- A signing certificate + provisioning profile that includes an **App Group**
- Change the App Group identifier in the code/entitlements if you use a different one

Default App Group used in this project:

```
group.com.huami.gestultx
```

(You can keep this if your cert already has it from GestaltX, or replace it with one you control.)

## Important

- This is a developer / power-user tool. Deleting system caches can temporarily break feature flags until the system regenerates them (usually after a reboot).
- Always make a backup first.
- Only use on devices you own or are authorized to manage.
- worse_query is GPL-3.0. This project includes its sources and must keep the license notices.

## How to build

1. Create a new **iOS App** project in Xcode (SwiftUI, Swift).
2. Delete the default ContentView / App file if you want, then drag the files from the `GestaltReset/` folder into your project.
3. Set the **Objective-C Bridging Header** to `GestaltReset/GestaltReset-Bridging-Header.h`.
4. Add the `.m` files to the target’s Compile Sources.
5. Enable **App Groups** capability and set the identifier to match the one in the entitlements / `ContentView.swift` (default: `group.com.huami.gestultx`).
6. Build & run on a real device (Simulator cannot access the SystemGroup path).

## License

- worse_query portions: GPL-3.0 (see LICENSE)
- The rest of this small UI wrapper: free to use, keep the worse_query attribution and GPL terms for the included code.
