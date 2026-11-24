import Foundation

/// A list as text: one line per row in left-aligned columns two spaces apart, the first row a
/// header in capitals. Every row has as many cells as the header.
public enum Table {
    public static func format(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let widths = header.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.map { row in
            zip(row, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
                .replacing(#/\s+$/#, with: "")
        }.joined(separator: "\n")
    }

    /// The table of `rows` under `header`, or nil when there are no rows: an empty list prints nothing.
    public static func format(header: [String], rows: [[String]]) -> String? {
        rows.isEmpty ? nil : format([header] + rows)
    }
}
