import SwiftUI
import FamilyControls

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showBlockedList = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                #if LITE
                liteSection
                #else
                statusSection
                if appState.pendingUnlock != nil {
                    pendingSection
                }
                blockedListSection
                if appState.protectionEnabled, !SharedStore.shared.blockedDomains.isEmpty {
                    websitesSection
                }
                #endif
            }
            .navigationTitle("PlusOne")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showBlockedList) { BlockedListView() }
        }
    }

    #if LITE
    // Lite build: blocking is unavailable; the camera check is tested directly.
    private var liteSection: some View {
        Section {
            Button {
                appState.showCapture = true
            } label: {
                Label("Test the selfie check", systemImage: "camera.fill")
                    .font(.headline)
            }
        } footer: {
            Text("Lite build: blocking is disabled. This runs the two-face camera check only.")
        }
    }
    #endif

    private var statusSection: some View {
        Section {
            Toggle(isOn: $appState.protectionEnabled) {
                Label(
                    appState.protectionEnabled ? "Protection on" : "Protection off",
                    systemImage: appState.protectionEnabled ? "shield.fill" : "shield.slash"
                )
                .foregroundStyle(appState.protectionEnabled ? .green : .secondary)
            }
            .disabled(appState.blockedItemCount == 0)

            ForEach(appState.activeSessions, id: \.id) { session in
                Label(
                    "Unlocked \(session.target.displayNoun): \(session.usageMinutes) min of usage",
                    systemImage: "lock.open.fill"
                )
                .foregroundStyle(.orange)
            }

            if appState.blockedItemCount == 0 {
                Text("Pick at least one app or website to protect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pendingSection: some View {
        Section {
            Button {
                // refresh() opens the capture flow for the stored request.
                appState.refresh()
            } label: {
                Label("Take your unlock selfie", systemImage: "camera.fill")
                    .font(.headline)
            }
        } footer: {
            Text("You tapped unlock on a blocked item. Pass the selfie check to open it.")
        }
    }

    // Filtered domains have no shield button in Safari; unlocks start here.
    private var websitesSection: some View {
        Section {
            ForEach(SharedStore.shared.blockedDomains, id: \.self) { domain in
                HStack {
                    Label(domain, systemImage: "globe")
                    Spacer()
                    if appState.activeSessions.contains(where: { $0.target == .domain(domain) }) {
                        Text("Unlocked")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Button("Unlock") {
                            appState.captureRequest = CaptureRequest(target: .domain(domain))
                        }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            Text("Blocked websites")
        } footer: {
            Text("Safari shows a restricted page for these; unlock them here.")
        }
    }

    private var blockedListSection: some View {
        Section {
            Button {
                showBlockedList = true
            } label: {
                Label("Edit blocked list", systemImage: "list.bullet")
            }
        } footer: {
            let domains = SharedStore.shared.blockedDomains.count
            Text("\(appState.blockedItemCount) app item(s), \(domains) website(s) blocked. Unlocking requires a selfie with at least two people in it.")
        }
    }
}
