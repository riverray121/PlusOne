import SwiftUI
import FamilyControls

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var queued: QueuedNotice?

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if appState.pendingUnlock != nil {
                    pendingSection
                }
                if pendingChangeCount > 0 {
                    pendingChangesSection
                }
                blockedListSection
                antiTamperSection
            }
            .navigationTitle("PlusOne")
            // Summary counts read SharedStore directly; re-render on return
            // from child screens so they never show stale values.
            .onAppear { appState.refresh() }
            .queuedChangeAlert($queued)
        }
    }

    private var statusSection: some View {
        Section {
            // Off is a weakening: route through the gate, which may queue it
            // and leave the toggle on.
            Toggle(isOn: Binding(
                get: { appState.protectionEnabled },
                set: { on in
                    if let change = appState.setProtection(on) {
                        queued = QueuedNotice(change)
                    }
                }
            )) {
                Label(
                    appState.protectionEnabled ? "Protection on" : "Protection off",
                    systemImage: appState.protectionEnabled ? "shield.fill" : "shield.slash"
                )
                .foregroundStyle(appState.protectionEnabled ? .green : .secondary)
            }
            .disabled(!hasAnyBlocking)

            ForEach(appState.activeSessions, id: \.id) { session in
                Label(
                    "Unlocked \(session.target.displayNoun): \(session.usageMinutes) min of usage",
                    systemImage: "lock.open.fill"
                )
                .foregroundStyle(.orange)
            }

            if !hasAnyBlocking {
                Text("Pick at least one app or website to protect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Protection is meaningful with any kind of blocking configured, not just
    // selfie-unlock items.
    private var hasAnyBlocking: Bool {
        appState.selfieBlockItemCount > 0
            || SharedStore.shared.hardSelection.itemCount > 0
            || SharedStore.shared.adultFilterEnabled
            || !SharedStore.shared.timeLimitRules.isEmpty
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
                    Text("\(appState.selfieBlockItemCount)")
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

    private var pendingChangesSection: some View {
        Section {
            NavigationLink {
                PendingChangesView()
            } label: {
                HStack {
                    Label("Pending changes", systemImage: "clock")
                    Spacer()
                    Text("\(pendingChangeCount)")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Changes waiting out your delay. Each one takes effect when its countdown ends.")
        }
    }

    private var antiTamperSection: some View {
        Section {
            NavigationLink {
                AntiTamperView()
            } label: {
                HStack {
                    Label("Anti-tamper", systemImage: "lock.shield")
                    Spacer()
                    Text(delayHoursLabel(SharedStore.shared.delayMinutes))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Makes loosening your protection slow and deliberate.")
        }
    }

    private var pendingChangeCount: Int {
        SharedStore.shared.pendingChanges.count
    }

    private var timeLimitSummary: String {
        let count = SharedStore.shared.timeLimitRules.count
        switch count {
        case 0: return "Off"
        case 1: return "1 limit"
        default: return "\(count) limits"
        }
    }

    private var hardBlockSummary: String {
        let count = SharedStore.shared.hardSelection.itemCount
        let adult = SharedStore.shared.adultFilterEnabled
        switch (count, adult) {
        case (0, false): return "Off"
        case (0, true): return "Adult"
        case (_, false): return "\(count) items"
        case (_, true): return "\(count) items + adult"
        }
    }
}
