import SwiftUI

// Permanent website blocks: preset services, custom domains, and Apple's
// adult-content filter. No selfie unlock; changes apply immediately while
// protection is on.
struct HardBlockView: View {
    @State private var blockedDomains = Set(SharedStore.shared.blockedDomains)
    @State private var customDomain = ""
    @State private var adultFilter = SharedStore.shared.adultFilterEnabled

    // Web counterparts of popular apps; a preset toggles all its domains.
    // iOS also restricts a domain's associated app while it is filtered.
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
        List {
                Section {
                    Toggle("Block adult websites", isOn: $adultFilter)
                        .onChange(of: adultFilter) { on in
                            SharedStore.shared.adultFilterEnabled = on
                            applyNow()
                        }
                } footer: {
                    #if DEBUG
                    Text("Apple's adult-content filter for Safari.\nstore: adult=\(SharedStore.shared.adultFilterEnabled ? "ON" : "off"), \(SharedStore.shared.blockedDomains.count) sites")
                    #else
                    Text("Apple's adult-content filter for Safari.")
                    #endif
                }

                Section {
                    ForEach(Self.presets, id: \.name) { preset in
                        Toggle(preset.name, isOn: presetBinding(preset.domains))
                    }
                } header: {
                    Text("Popular sites")
                }

                Section {
                    HStack {
                        TextField("other-site.com", text: $customDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("Add") { addCustomDomain() }
                            .bold()
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
                    Text("Custom sites")
                } footer: {
                    Text("Hard blocks have no selfie unlock. iOS also restricts each site's matching app while its domain is blocked. For selfie-unlockable blocking, use the Photo Block tab.")
                }
            }
        .navigationTitle("Hard blocks")
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Helpers

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
        applyNow()
    }

    private func applyNow() {
        guard SharedStore.shared.protectionEnabled else { return }
        // Full clear-then-reapply pulse: replicates the protection off/on
        // cycle, which is what reliably dislodges a stuck web filter.
        ShieldController.shared.clearShields()
        SessionManager.shared.refreshShields()
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
