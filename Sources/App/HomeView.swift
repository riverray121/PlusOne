import SwiftUI
import FamilyControls

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showPicker = false
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
            .familyActivityPicker(isPresented: $showPicker, selection: $appState.selection)
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

            if let session = appState.activeSession {
                Label(
                    "Session active: \(session.usageMinutes) min of \(session.target.displayNoun) usage granted",
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
                appState.showCapture = true
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
            Button {
                showPicker = true
            } label: {
                Label("Edit blocked list", systemImage: "list.bullet")
            }
        } footer: {
            Text("\(appState.blockedItemCount) item(s) blocked. Unlocking requires a selfie with at least two people in it.")
        }
    }
}
