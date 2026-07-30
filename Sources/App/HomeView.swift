import SwiftUI
import FamilyControls

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

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
                #endif
            }
            .navigationTitle("PlusOne")
            // Summary counts read SharedStore directly; re-render on return
            // from child screens so they never show stale values.
            .onAppear { appState.refresh() }
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

    private var blockedListSection: some View {
        Section {
            NavigationLink {
                SelfieBlockView()
            } label: {
                HStack {
                    Label("Selfie-unlock blocks", systemImage: "person.2.fill")
                    Spacer()
                    Text("\(appState.blockedItemCount)")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                HardBlockView()
            } label: {
                HStack {
                    Label("Hard blocks", systemImage: "nosign")
                    Spacer()
                    Text(hardBlockSummary)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                TimeLimitsView()
            } label: {
                HStack {
                    Label("Time limits", systemImage: "hourglass")
                    Spacer()
                    Text(timeLimitSummary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Blocking")
        } footer: {
            Text("Selfie-unlock blocks open after a selfie with at least two people. Hard blocks never open. Time limits grant a budget of minutes per hour or day.")
        }
    }

    private var timeLimitSummary: String {
        let count = SharedStore.shared.timeLimitRules.count
        return count == 0 ? "Off" : (count == 1 ? "1 limit" : "\(count) limits")
    }

    private var hardBlockSummary: String {
        let hard = SharedStore.shared.hardSelection
        let count = hard.applicationTokens.count
            + hard.webDomainTokens.count
            + hard.categoryTokens.count
        let adult = SharedStore.shared.adultFilterEnabled
        switch (count, adult) {
        case (0, false): return "Off"
        case (0, true): return "Adult"
        case (_, false): return "\(count) items"
        case (_, true): return "\(count) items + adult"
        }
    }
}
