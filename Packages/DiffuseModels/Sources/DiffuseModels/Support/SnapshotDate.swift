import Foundation

public extension Date {
    /// Rounds to whole milliseconds.
    ///
    /// `Date` is a `Double`, but the serialized format is ISO-8601 with
    /// millisecond precision because a readable, hand-diffable snapshot file is
    /// worth more than nanoseconds nobody will ever look at. Rounding on the
    /// way *in* means a snapshot round-trips through JSON byte-for-byte, which
    /// is the property golden fixtures and `diff(A, A) == ∅` both depend on.
    func roundedForSnapshot() -> Date {
        // Integer milliseconds, then divide. Constructing via `/ 1000` on a
        // rounded Double can leave a residue (808723250.646 vs .6459999)
        // that DateFormatter then fails to round-trip.
        let millis = Int64((timeIntervalSinceReferenceDate * 1000).rounded())
        return Date(timeIntervalSinceReferenceDate: TimeInterval(millis) / 1000)
    }
}

public extension PropertyValue {
    /// Builds a date-valued property, rounded to the serialized resolution.
    ///
    /// Collectors should prefer this over `.date(_:)` so that the value they
    /// record is exactly the value that comes back after a save and load.
    static func timestamp(_ date: Date) -> PropertyValue {
        .date(date.roundedForSnapshot())
    }
}
