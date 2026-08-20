import AppKit
import DiffuseCore
import DiffuseModels
import DiffuseUI
import SwiftUI

/// Everything Diffuse can observe on this Mac, and whether it can right now.
struct CapabilitiesView: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                header

                CapabilityListView(
                    statuses: model.capabilities,
                    onToggle: { id, isEnabled in
                        Task { await model.setCapabilityEnabled(isEnabled, for: id) }
                    },
                    onRequestPermission: { requirement in
                        guard let url = requirement.settingsURL else { return }
                        NSWorkspace.shared.open(url)
                    }
                )
            }
            .padding(DiffuseTheme.Spacing.large)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .diffuseCanvas()
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refreshCapabilities() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .help("Probe every capability again")
            }
        }
        .task { await model.refreshCapabilities() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            Text("Capabilities")
                .font(.largeTitle.weight(.semibold))
            Text("Diffuse discovers what it can observe at launch. Tools you do not have installed simply do not "
                + "appear — there is no list of things you are missing.")
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The generated privacy disclosure.
struct PrivacyView: View {
    @Environment(DiffuseModel.self) private var model
    @State private var ledger: PrivacyLedger?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    Text("Privacy")
                        .font(.largeTitle.weight(.semibold))
                    Text("This page is generated from the capabilities actually compiled into this build, so it "
                        + "cannot drift out of date.")
                        .font(.callout)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let ledger {
                    PrivacyLedgerView(ledger: ledger)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(DiffuseTheme.Spacing.large)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .diffuseCanvas()
        .task { ledger = await model.privacyLedger() }
    }
}
