//
//  ContentView.swift
//  GestaltReset
//

import SwiftUI

struct ContentView: View {
    @State private var log = "GestaltReset ready.\nRequires a working App Group entitlement.\n"
    @State private var isBusy = false
    @State private var lastStatus = "Idle"
    @State private var showDeleteConfirm = false
    @State private var showClearCachesConfirm = false

    // Change this to an App Group you control and that is present in your signing profile.
    // GestaltX uses group.com.huami.gestultx — you can reuse that if your cert has it.
    private let appGroup = "group.com.huami.gestultx"

    // Exact path GestaltX writes to
    private let mobileGestaltPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    private let systemGroupRoot = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: lastStatus)
                    LabeledContent("App Group", value: appGroup)
                } header: {
                    Text("Info")
                } footer: {
                    Text("This tool uses worse_query to reach the SystemGroup path that holds the MobileGestalt cache. You must sign the app with an App Group entitlement that matches the one above (or change the constant).")
                }

                Section("MobileGestalt") {
                    Button {
                        Task { await backupMobileGestalt() }
                    } label: {
                        Label("Backup current MobileGestalt.plist", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(isBusy)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete MobileGestalt.plist", systemImage: "trash")
                    }
                    .disabled(isBusy)

                    Button(role: .destructive) {
                        showClearCachesConfirm = true
                    } label: {
                        Label("Clear SystemGroup caches", systemImage: "xmark.bin")
                    }
                    .disabled(isBusy)
                }

                Section("Log") {
                    ScrollView {
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 180)

                    Button("Clear Log") {
                        log = ""
                    }
                }
            }
            .navigationTitle("GestaltReset")
            .toolbar {
                if isBusy {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
            }
            .alert("Delete MobileGestalt.plist?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteMobileGestalt() }
                }
            } message: {
                Text("This removes the system MobileGestalt cache file. iOS will usually regenerate it after a reboot or when the system needs it. A backup is made first if possible. Use only on devices you own.")
            }
            .alert("Clear SystemGroup caches?", isPresented: $showClearCachesConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task { await clearSystemGroupCaches() }
                }
            } message: {
                Text("This removes files under the mobilegestaltcache SystemGroup (including the plist). The system may recreate them. A backup of the main plist is attempted first.")
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func appendLog(_ line: String) {
        log += line + "\n"
    }

    private func withAccess<T>(_ body: (URL) throws -> T) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let targetDir = (mobileGestaltPath as NSString).deletingLastPathComponent
                let handle = worse_query(targetDir, appGroup, false, false)

                guard handle >= 0 else {
                    let msg: String
                    switch handle {
                    case -1: msg = "No usable App Group (check signing / entitlement)."
                    case -2: msg = "Failed to resolve container manager functions (unsupported OS?)."
                    case -3: msg = "Failed to create query."
                    case -4: msg = "Failed to create symlink."
                    case -5: msg = "Query rejected by containermanagerd."
                    case -6: msg = "Kernel refused sandbox extension."
                    case -255: msg = "Target path does not exist."
                    default: msg = "worse_query failed with code \(handle)."
                    }
                    continuation.resume(returning: .failure(NSError(domain: "GestaltReset", code: Int(handle), userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }

                defer { worse_query_release(handle) }

                let url = URL(fileURLWithPath: mobileGestaltPath)
                do {
                    let result = try body(url)
                    continuation.resume(returning: .success(result))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    @MainActor
    private func backupMobileGestalt() async {
        isBusy = true
        lastStatus = "Backing up…"
        appendLog("--- Backup ---")

        let result = await withAccess { url in
            let data = try Data(contentsOf: url)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let dest = docs.appendingPathComponent("MobileGestalt-backup-\(stamp).plist")
            try data.write(to: dest, options: .atomic)
            return (dest, data.count)
        }

        switch result {
        case .success(let (dest, size)):
            appendLog("Backup saved: \(dest.lastPathComponent) (\(size) bytes)")
            lastStatus = "Backup OK"
        case .failure(let error):
            appendLog("Backup failed: \(error.localizedDescription)")
            lastStatus = "Backup failed"
        }
        isBusy = false
    }

    @MainActor
    private func deleteMobileGestalt() async {
        isBusy = true
        lastStatus = "Deleting…"
        appendLog("--- Delete MobileGestalt.plist ---")

        _ = await withAccess { url in
            if let data = try? Data(contentsOf: url) {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let dest = docs.appendingPathComponent("MobileGestalt-predelete-\(stamp).plist")
                try? data.write(to: dest, options: .atomic)
                appendLog("Pre-delete backup attempted.")
            }
            return ()
        }

        let result = await withAccess { url in
            try FileManager.default.removeItem(at: url)
            return ()
        }

        switch result {
        case .success:
            appendLog("MobileGestalt.plist deleted.")
            lastStatus = "Deleted"
        case .failure(let error):
            appendLog("Delete failed: \(error.localizedDescription)")
            lastStatus = "Delete failed"
        }
        isBusy = false
    }

    @MainActor
    private func clearSystemGroupCaches() async {
        isBusy = true
        lastStatus = "Clearing caches…"
        appendLog("--- Clear SystemGroup caches ---")

        let result = await withAccess { _ in
            let root = URL(fileURLWithPath: systemGroupRoot)
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                throw NSError(domain: "GestaltReset", code: -10, userInfo: [NSLocalizedDescriptionKey: "Could not list SystemGroup root"])
            }

            var removed = 0
            for item in items {
                if item.lastPathComponent == "Library" {
                    let caches = item.appendingPathComponent("Caches")
                    if fm.fileExists(atPath: caches.path) {
                        if let cacheItems = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
                            for c in cacheItems {
                                try? fm.removeItem(at: c)
                                removed += 1
                                appendLog("Removed: \(c.lastPathComponent)")
                            }
                        }
                    }
                }
            }
            return removed
        }

        switch result {
        case .success(let count):
            appendLog("Cleared \(count) item(s) under SystemGroup caches.")
            lastStatus = "Caches cleared"
        case .failure(let error):
            appendLog("Clear failed: \(error.localizedDescription)")
            lastStatus = "Clear failed"
        }
        isBusy = false
    }
}
