import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Report renderer")
struct ReportRendererTests {
    private func pair() -> (base: Snapshot, target: Snapshot, diff: DiffResult) {
        let base = SnapshotBuilder(id: "before")
            .labelled("Before")
            .withWidgets([TestSchema.entity("one", name: "Alpha", value: .string("old"))])
            .build()
        let target = SnapshotBuilder(id: "after", capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(3600))
            .labelled("After")
            .withWidgets([TestSchema.entity("one", name: "Alpha", value: .string("new"))])
            .build()
        return (base, target, DiffEngine().diff(base: base, target: target))
    }

    @Test("A diff report names both snapshots and the local-only footer")
    func diffReport() {
        let report = ReportRenderer.markdown(for: pair().diff)
        #expect(report.contains("# Diffuse Report"))
        #expect(report.contains("Before"))
        #expect(report.contains("After"))
        #expect(report.contains("No data left this device"))
        #expect(report.hasSuffix("\n"))
    }

    @Test("Severity filtering can empty a report without dropping the header")
    func severityFilter() {
        let report = ReportRenderer.markdown(for: pair().diff, minimumSeverity: .critical)
        #expect(report.contains("# Diffuse Report"))
        #expect(report.contains("No changes at this severity"))
    }

    @Test("Markdown special characters in values are escaped")
    func escaping() {
        let base = SnapshotBuilder(id: "b").withWidgets([
            TestSchema.entity("one", name: "Thing", value: .string("plain")),
        ]).build()
        let target = SnapshotBuilder(id: "t").withWidgets([
            TestSchema.entity("one", name: "Thing", value: .string("a * b_c [x]")),
        ]).build()
        let report = ReportRenderer.markdown(for: DiffEngine().diff(base: base, target: target))
        #expect(report.contains("\\*"))
        #expect(report.contains("\\_"))
    }

    @Test("An empty self-diff says so")
    func emptyDiff() {
        let snapshot = SnapshotBuilder().withWidgets([TestSchema.entity("one")]).build()
        let report = ReportRenderer.markdown(for: DiffEngine().selfDiff(snapshot))
        #expect(report.contains("No changes") || report.contains("_No changes"))
    }

    @Test("A snapshot inventory lists the section and entities")
    func snapshotInventory() {
        let snapshot = SnapshotBuilder(id: "inv")
            .labelled("Inventory")
            .withWidgets([TestSchema.entity("one", name: "Alpha", value: .string("hello"))])
            .build()
        let report = ReportRenderer.markdown(for: snapshot)
        #expect(report.contains("# Snapshot — Inventory"))
        #expect(report.contains("## Widgets"))
        #expect(report.contains("### Alpha"))
        #expect(report.contains("hello"))
    }

    @Test("A section without data renders its status instead of entities")
    func emptySectionStatus() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [], status: .permissionRequired))
            .build()
        let report = ReportRenderer.markdown(for: snapshot)
        #expect(report.contains(CollectionStatus.permissionRequired.displayName))
        #expect(!report.contains("### "))
    }

    @Test("Plain text rendering is colour-free")
    func plainText() {
        let text = ReportRenderer.plainText(for: pair().diff)
        #expect(text.contains("Diffuse Diff"))
        #expect(!text.contains("\u{001B}"))
        #expect(!text.contains("[32m"))
    }

    @Test("Plain text respects a severity floor")
    func plainTextSeverity() {
        let text = ReportRenderer.plainText(for: pair().diff, minimumSeverity: .critical)
        #expect(text.contains("Diffuse Diff"))
    }
}
