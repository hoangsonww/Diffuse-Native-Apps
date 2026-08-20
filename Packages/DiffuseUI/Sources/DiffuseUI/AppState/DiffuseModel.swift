import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import Observation
import SwiftUI

/// The observable state every Diffuse app is built on.
///
/// Shared across macOS, iOS, iPadOS and watchOS because "take a snapshot, list
/// them, compare two of them" is product behaviour, not platform behaviour.
/// What the four apps do *not* share is how any of it looks — each drives this
/// from its own genuinely native navigation.
@MainActor
@Observable
public final class DiffuseModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case capturing
        case ready
        case failed(String)

        public var isBusy: Bool {
            self == .loading || self == .capturing
        }

        public var failureMessage: String? {
            if case let .failed(message) = self {
                return message
            }
            return nil
        }
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle
    public private(set) var summaries: [SnapshotSummary] = []
    public private(set) var overview: SnapshotService.Overview?
    public private(set) var capabilities: [CapabilityStatus] = []
    public private(set) var storageBytes: Int64 = 0

    /// The last capture's per-collector outcomes, shown in diagnostics.
    public private(set) var lastCaptureReport: CaptureReport?

    /// The two snapshots the user picked to compare. Order is base then target.
    public var comparisonSelection: [SnapshotID] = []
    public private(set) var comparison: DiffResult?

    /// Filters applied to the comparison screen.
    public var minimumSeverity: ChangeSeverity = .informational
    public var searchText: String = ""

    /// Library search (snapshots, sections, entities), distinct from the
    /// comparison change filter.
    public var libraryQuery: String = ""
    public private(set) var libraryResults: [SearchResult] = []

    private var searchIndex: SearchIndex?

    private let service: SnapshotService

    public init(service: SnapshotService) {
        self.service = service
    }

    // MARK: - Loading

    public func load() async {
        if phase == .idle {
            phase = .loading
        }
        await refreshEverything()
    }

    public func refresh() async {
        await refreshEverything()
    }

    private func refreshEverything() async {
        do {
            async let summaries = service.summaries()
            async let overview = service.overview()
            async let storage = service.storageSize()

            self.summaries = try await summaries
            self.overview = try await overview
            storageBytes = try await storage
            searchIndex = nil
            if !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await searchLibrary(libraryQuery)
            }
            phase = .ready
        } catch {
            phase = .failed(Self.describe(error))
        }

        capabilities = await service.capabilityStatuses()
        await recomputeComparison()
    }

    /// Probes availability again. Separate from `refresh` because probing can
    /// spawn subprocesses, and the timeline should not pay for that.
    public func refreshCapabilities() async {
        capabilities = await service.refreshCapabilities().filter(\.availability.isDiscoverable)
    }

    // MARK: - Capture

    @discardableResult
    public func capture(
        label: String? = nil,
        origin: SnapshotOrigin = .manual,
        isBackground: Bool = false,
        skipIfUnchanged: Bool = false
    ) async -> Bool {
        guard phase != .capturing else { return false }
        phase = .capturing

        do {
            let report = try await service.capture(
                origin: origin,
                label: label,
                isBackground: isBackground,
                skipIfUnchanged: skipIfUnchanged
            )
            if report.didPersist {
                lastCaptureReport = report
            }
            await refreshEverything()
            return report.didPersist
        } catch {
            phase = .failed(Self.describe(error))
            return false
        }
    }

    // MARK: - Annotations

    public func setPinned(_ isPinned: Bool, for id: SnapshotID) async {
        await annotate(id: id, with: SnapshotAnnotation(isPinned: isPinned))
    }

    public func setLabel(_ label: String, for id: SnapshotID) async {
        await annotate(id: id, with: SnapshotAnnotation(label: label))
    }

    private func annotate(id: SnapshotID, with annotation: SnapshotAnnotation) async {
        do {
            try await service.annotate(id: id, with: annotation)
            await refreshEverything()
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    public func delete(id: SnapshotID) async {
        do {
            try await service.delete(id: id)
            comparisonSelection.removeAll { $0 == id }
            await refreshEverything()
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    public func deleteAll() async {
        do {
            try await service.deleteAll()
            comparisonSelection.removeAll()
            comparison = nil
            await refreshEverything()
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    // MARK: - Comparison

    /// Toggles a snapshot in the comparison selection, keeping at most two.
    ///
    /// Selecting a third replaces the older of the pair, which is what people
    /// expect from a two-slot picker and avoids a modal "clear selection" step.
    public func toggleComparison(_ id: SnapshotID) {
        if let index = comparisonSelection.firstIndex(of: id) {
            comparisonSelection.remove(at: index)
        } else {
            comparisonSelection.append(id)
            if comparisonSelection.count > 2 {
                comparisonSelection.removeFirst()
            }
        }
        Task { await recomputeComparison() }
    }

    public func compare(base: SnapshotID, target: SnapshotID) {
        comparisonSelection = [base, target]
        Task { await recomputeComparison() }
    }

    /// Selects the two most recent snapshots.
    public func compareLatest() {
        guard summaries.count >= 2 else { return }
        comparisonSelection = [summaries[1].id, summaries[0].id]
        Task { await recomputeComparison() }
    }

    public func clearComparison() {
        comparisonSelection.removeAll()
        comparison = nil
    }

    public func selectionOrder(of id: SnapshotID) -> Int? {
        comparisonSelection.firstIndex(of: id).map { $0 + 1 }
    }

    public func searchLibrary(_ query: String) async {
        libraryQuery = query
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            libraryResults = []
            return
        }
        do {
            if searchIndex == nil {
                let snapshots = try await service.snapshots()
                searchIndex = SearchIndex(snapshots: snapshots)
            }
            libraryResults = searchIndex?.search(needle) ?? []
        } catch {
            libraryResults = []
            phase = .failed(Self.describe(error))
        }
    }

    public var isSearchingLibrary: Bool {
        !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recomputeComparison() async {
        guard comparisonSelection.count == 2 else {
            comparison = nil
            return
        }

        // Always compare oldest to newest regardless of the order they were
        // tapped in; a diff that runs backwards is confusing, not clever.
        let ordered = orderedSelection()
        do {
            comparison = try await service.diff(base: ordered.base, target: ordered.target)
        } catch {
            comparison = nil
            phase = .failed(Self.describe(error))
        }
    }

    private func orderedSelection() -> (base: SnapshotID, target: SnapshotID) {
        let dates = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.capturedAt) })
        let first = comparisonSelection[0]
        let second = comparisonSelection[1]
        guard let firstDate = dates[first], let secondDate = dates[second] else {
            return (base: first, target: second)
        }
        return firstDate <= secondDate ? (base: first, target: second) : (base: second, target: first)
    }

    /// The changes to show, after severity filtering and text search.
    public var visibleChanges: [Change] {
        guard let comparison else { return [] }
        let filtered = comparison.changes.filtered(minimumSeverity: minimumSeverity)
        guard !searchText.isEmpty else { return filtered }
        return ChangeSearchIndex(changes: filtered).search(searchText)
    }

    public var visibleSections: [SectionDiff] {
        guard let comparison else { return [] }
        let visible = Set(visibleChanges.map(\.id))
        return comparison.sectionDiffs.compactMap { section in
            let changes = section.changes.filter { visible.contains($0.id) }
            guard !changes.isEmpty else { return nil }
            return SectionDiff(
                capability: section.capability,
                displayName: section.displayName,
                category: section.category,
                symbol: section.symbol,
                baseStatus: section.baseStatus,
                targetStatus: section.targetStatus,
                changes: changes,
                unchangedEntityCount: section.unchangedEntityCount
            )
        }
    }

    // MARK: - Detail

    public func snapshot(id: SnapshotID) async -> Snapshot? {
        try? await service.snapshot(id: id)
    }

    public func privacyLedger() async -> PrivacyLedger {
        await service.privacyLedger()
    }

    public func setCapabilityEnabled(_ isEnabled: Bool, for id: CapabilityID) async {
        await service.setCapabilityEnabled(isEnabled, for: id)
        capabilities = await service.capabilityStatuses()
    }

    // MARK: - Export

    public func markdownReport(redaction: RedactionPolicy = .standard) async -> String? {
        guard comparisonSelection.count == 2 else { return nil }
        let ordered = orderedSelection()
        return try? await service.exportReport(
            base: ordered.base,
            target: ordered.target,
            minimumSeverity: minimumSeverity,
            redaction: redaction
        )
    }

    public func exportSnapshot(id: SnapshotID, redaction: RedactionPolicy = .standard) async -> Data? {
        try? await service.exportSnapshot(id: id, redaction: redaction)
    }

    public func exportComparison(redaction: RedactionPolicy = .standard) async -> Data? {
        guard comparisonSelection.count == 2 else { return nil }
        let ordered = orderedSelection()
        return try? await service.exportDiff(base: ordered.base, target: ordered.target, redaction: redaction)
    }

    @discardableResult
    public func importSnapshot(from data: Data) async -> Bool {
        do {
            _ = try await service.importSnapshot(from: data)
            await refreshEverything()
            return true
        } catch {
            phase = .failed(Self.describe(error))
            return false
        }
    }

    // MARK: - Derived

    public func dismissFailure() {
        guard case .failed = phase else { return }
        phase = summaries.isEmpty ? .idle : .ready
    }

    public func reportFailure(_ message: String) {
        phase = .failed(message)
    }

    public func setRetentionPolicy(_ policy: RetentionPolicy) async {
        await service.setRetentionPolicy(policy)
    }

    public var failureMessage: String? {
        phase.failureMessage
    }

    public var hasSnapshots: Bool {
        !summaries.isEmpty
    }

    public var canCompare: Bool {
        summaries.count >= 2
    }

    public var latestSummary: SnapshotSummary? {
        summaries.first
    }

    public var formattedStorage: String {
        storageBytes.formatted(.byteCount(style: .file))
    }

    public var availableCapabilityCount: Int {
        capabilities.count { $0.availability.isAvailable }
    }

    /// Capabilities that need the user to do something, surfaced on the
    /// overview so a permission problem is not silently swallowed.
    public var actionableCapabilities: [CapabilityStatus] {
        capabilities.filter {
            if case .permissionRequired = $0.availability {
                return true
            }
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        error.localizedDescription
    }
}
