import SwiftUI
import FamilyControls

// The full blocked list: picker-based apps/categories plus PlusOne's own
// website blocklist, managed in one place.
struct BlockedListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var blockedDomains = Set(SharedStore.shared.blockedDomains)
    @State private var customDomain = ""

    // Web counterparts of popular apps; a preset toggles all its domains.
    // iOS associates apps with their domains, so filtering a domain also
    // restricts the matching app.
    private static let presets: [(name: String, domains: [String])] = [
        ("Instagram", ["instagram.com"]),
        ("TikTok", ["tiktok.com"]),
        ("X (Twitter)", ["x.com", "twitter.com"]),
        ("YouTube", ["youtube.com"]),
        ("Reddit", ["reddit.com"]),
        ("Facebook", ["facebook.com"]),
        ("Snapchat", ["snapchat.com"]),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose apps and categories", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("\(appState.blockedItemCount) selected in the system picker.")
                }

                Section {
                    ForEach(Self.presets, id: \.name) { preset in
                        Toggle(preset.name, isOn: presetBinding(preset.domains))
                    }
                    HStack {
                        TextField("other-site.com", text: $customDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("Add") { addCustomDomain() }
                            .disabled(Self.sanitize(customDomain) == nil)
                    }
                    ForEach(customDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button {
                                blockedDomains.remove(domain)
                                persistDomains()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Websites")
                } footer: {
                    Text("Blocked in Safari via the Screen Time filter; iOS also restricts each site's matching app. Unlock from the PlusOne home screen.")
                }
            }
            .navigationTitle("Blocked list")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $appState.selection)
        }
    }

    // MARK: Website helpers

    private var customDomains: [String] {
        let presetDomains = Set(Self.presets.flatMap(\.domains))
        return blockedDomains.subtracting(presetDomains).sorted()
    }

    private func presetBinding(_ domains: [String]) -> Binding<Bool> {
        Binding(
            get: { domains.allSatisfy { blockedDomains.contains($0) } },
            set: { on in
                if on {
                    blockedDomains.formUnion(domains)
                } else {
                    blockedDomains.subtract(domains)
                }
                persistDomains()
            }
        )
    }

    private func addCustomDomain() {
        guard let domain = Self.sanitize(customDomain) else { return }
        blockedDomains.insert(domain)
        customDomain = ""
        persistDomains()
    }

    private func persistDomains() {
        SharedStore.shared.blockedDomains = Array(blockedDomains)
        if SharedStore.shared.protectionEnabled {
            SessionManager.shared.refreshShields()
        }
    }

    // "https://www.Reddit.com/r/all" -> "reddit.com"
    private static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        s = String(s.prefix(while: { $0 != "/" }))
        guard s.contains("."), !s.contains(" "), s.count > 3 else { return nil }
        return s
    }
}
