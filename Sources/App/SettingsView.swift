import SwiftUI

// The whole settings surface: duration, cooldown, daily cap, websites.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var duration = SharedStore.shared.durationMinutes
    @State private var cooldown = SharedStore.shared.cooldownMinutes
    @State private var cap = SharedStore.shared.dailyCap
    @State private var blockedDomains = Set(SharedStore.shared.blockedDomains)
    @State private var customDomain = ""

    private let durationOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    private let cooldownOptions = [0, 5, 15, 30, 60, 120]
    private let capOptions = Array(0...10)

    // Web counterparts of popular apps; a preset toggles all its domains.
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
            Form {
                Section {
                    Picker("Unlock duration", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { Text("\($0) min") }
                    }
                    .onChange(of: duration) { SharedStore.shared.durationMinutes = $0 }
                } footer: {
                    Text("Minutes of usage granted per selfie pass. Applies to the next session.")
                }

                Section {
                    Picker("Cooldown", selection: $cooldown) {
                        ForEach(cooldownOptions, id: \.self) {
                            Text($0 == 0 ? "Off" : "\($0) min")
                        }
                    }
                    .onChange(of: cooldown) { SharedStore.shared.cooldownMinutes = $0 }
                } footer: {
                    Text("Wait required between unlock sessions.")
                }

                Section {
                    Picker("Daily cap", selection: $cap) {
                        ForEach(capOptions, id: \.self) {
                            Text($0 == 0 ? "Off" : "\($0) sessions")
                        }
                    }
                    .onChange(of: cap) { SharedStore.shared.dailyCap = $0 }
                } footer: {
                    Text("Maximum unlock sessions per day.")
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
                    Text("Blocked websites")
                } footer: {
                    Text("Websites are blocked in Safari via the Screen Time filter. Unlock them with a selfie from the PlusOne home screen; website sessions last at least 15 minutes (an iOS floor).")
                }

                Section {
                    Label("All processing happens on this device. Selfie frames are analyzed in memory and never stored.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Website blocklist helpers

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
