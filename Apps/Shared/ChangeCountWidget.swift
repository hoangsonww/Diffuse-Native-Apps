#if canImport(WidgetKit)
import DiffuseModels
import DiffuseUI
import SwiftUI
import WidgetKit

/// A home-screen / lock-screen widget that answers "how many changes?"
///
/// One number, because that is the whole point of a widget. Tapping it
/// opens the app, where the changes actually are.
struct ChangeCountWidget: Widget {
    let kind: String
    let store: ChangeCountStore

    init(kind: String, store: ChangeCountStore) {
        self.kind = kind
        self.store = store
    }

    /// WidgetKit requires a parameterless initializer.
    init() {
        #if os(watchOS)
        self.init(kind: "com.diffuse.watch.complication", store: .watch)
        #else
        self.init(kind: "com.diffuse.change-count", store: .iOS)
        #endif
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChangeCountProvider(store: store)) { entry in
            ChangeCountWidgetView(summary: entry.summary)
                .containerBackground(for: .widget) {
                    #if os(watchOS)
                    Color.clear
                    #else
                    DiffuseTheme.Palette.paper
                    #endif
                }
        }
        .configurationDisplayName("Changes")
        .description("How many meaningful changes there have been since the previous snapshot.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct ChangeCountEntry: TimelineEntry {
    let date: Date
    let summary: ChangeCountSummary
}

struct ChangeCountProvider: TimelineProvider {
    let store: ChangeCountStore

    func placeholder(in _: Context) -> ChangeCountEntry {
        ChangeCountEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ChangeCountEntry) -> Void) {
        completion(ChangeCountEntry(
            date: Date(),
            summary: context.isPreview ? .placeholder : store.read()
        ))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ChangeCountEntry>) -> Void) {
        let entry = ChangeCountEntry(date: Date(), summary: store.read())
        // The count only changes when the app takes a snapshot, and the app
        // reloads the timeline itself when it does. The hourly refresh is a
        // safety net, not the mechanism.
        completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 3600))))
    }
}

struct ChangeCountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let summary: ChangeCountSummary

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(summary.changeCount) changes", systemImage: "circle.hexagongrid")

        #if os(watchOS)
        case .accessoryCorner:
            Text("Δ\(summary.changeCount)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .widgetLabel("Diffuse")
        #endif

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Diffuse", systemImage: "circle.hexagongrid")
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(headline)
                    .font(.headline)
                if let capturedAt = summary.capturedAt {
                    Text(capturedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        #if os(iOS)
        case .systemMedium:
            HStack(alignment: .center, spacing: 16) {
                deltaBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diffuse")
                        .font(.headline)
                        .foregroundStyle(DiffuseTheme.Palette.ink)
                    Text(headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let capturedAt = summary.capturedAt {
                        Text("Last look \(capturedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        #endif

        default:
            deltaBadge
        }
    }

    private var deltaBadge: some View {
        ZStack {
            #if os(watchOS)
            AccessoryWidgetBackground()
            #endif
            VStack(spacing: -2) {
                Text("Δ")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                Text("\(summary.changeCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DiffuseTheme.Palette.ink)
                    .contentTransition(.numericText())
            }
        }
    }

    private var headline: String {
        summary.changeCount == 1 ? "1 change" : "\(summary.changeCount) changes"
    }

    private var tint: Color {
        summary.peakSeverity?.color ?? DiffuseTheme.Palette.accent
    }
}
#endif
