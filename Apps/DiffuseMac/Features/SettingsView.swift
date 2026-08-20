import AppKit
import DiffuseCore
import DiffuseModels
import DiffuseUI
import SwiftUI

struct SettingsView: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        TabView {
            ScheduleSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            RepositorySettings()
                .tabItem { Label("Repositories", systemImage: "arrow.triangle.branch") }
            StorageSettings()
                .tabItem { Label("Library", systemImage: "internaldrive") }
        }
        .padding(DiffuseTheme.Spacing.regular)
        .tint(DiffuseTheme.Palette.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiffuseTheme.Palette.canvas)
        .diffuseFailureBanner(model)
    }
}

struct ScheduleSettings: View {
    @Environment(MacSettings.self) private var settings
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        Form {
            PreferenceSettingsSections(
                preferences: settings.preferences,
                model: model,
                systemEventLabel: "Also capture when this Mac wakes"
            )
        }
        .formStyle(.grouped)
    }
}

struct RepositorySettings: View {
    @Environment(MacSettings.self) private var settings
    @State private var isChoosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            Text("Diffuse records only branch, commit and file counts for the repositories you choose. It never "
                + "reads file contents, commit messages or remote paths, and never touches the network.")
                .font(.caption)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(settings.watchedRepositoryPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(DiffuseTheme.Palette.accent)
                        Text((path as NSString).lastPathComponent)
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button {
                            settings.removeRepository(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .overlay {
                if settings.watchedRepositoryPaths.isEmpty {
                    Text("No repositories are being watched.")
                        .font(.callout)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                }
            }

            Button("Add Repository…") { isChoosing = true }
        }
        .padding(DiffuseTheme.Spacing.regular)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            settings.addRepository(url.path)
        }
    }
}

struct StorageSettings: View {
    @Environment(DiffuseModel.self) private var model
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Snapshots", value: "\(model.summaries.count)")
                LabeledContent("On disk", value: model.formattedStorage)
                Button("Delete All Snapshots…", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete every snapshot?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task { await model.deleteAll() }
            }
        } message: {
            Text("This permanently removes your entire snapshot history, including pinned snapshots. It cannot "
                + "be undone.")
        }
    }
}
