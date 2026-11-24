// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Lot 9, the disk map: what takes room, drawn as rectangles whose area is
/// their size. Pure: sizes come in, rectangles go out.
enum ForkDiskMapLogic {
    /// Squarified treemap (Bruls, Huizing, van Wijk): rows laid along the
    /// shorter side, each kept while it makes the rectangles squarer. Sizes
    /// largest first give the best shapes; the result keeps their order.
    static func squarify(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        let total = sizes.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return sizes.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { max(0, $0) * scale }
        var result = [CGRect](repeating: .zero, count: sizes.count)
        var free = rect
        var index = 0
        while index < areas.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else { break }
            var row = [index]
            var rowArea = areas[index]
            var next = index + 1
            while next < areas.count {
                let candidate = rowArea + areas[next]
                if worst(row.map { areas[$0] } + [areas[next]], sum: candidate, side: side)
                    > worst(row.map { areas[$0] }, sum: rowArea, side: side) { break }
                row.append(next)
                rowArea = candidate
                next += 1
            }
            // Lay the row along the shorter side of what is left.
            let thickness = CGFloat(rowArea / side)
            var offset: CGFloat = 0
            for item in row {
                let length = rowArea > 0 ? CGFloat(areas[item] / rowArea) * CGFloat(side) : 0
                if free.width >= free.height {
                    result[item] = CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                } else {
                    result[item] = CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                }
                offset += length
            }
            if free.width >= free.height {
                free = CGRect(x: free.minX + thickness, y: free.minY, width: max(0, free.width - thickness), height: free.height)
            } else {
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: max(0, free.height - thickness))
            }
            index = next
        }
        return result
    }

    /// The worst aspect ratio in a row: how far from square its least square rectangle is.
    private static func worst(_ areas: [Double], sum: Double, side: Double) -> Double {
        guard sum > 0, side > 0, let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        let side2 = side * side, sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }

    /// What a folder shows: its largest items, the rest gathered as one,
    /// so the map stays readable. `limit` items at most, and none under
    /// `minimumShare` of the whole.
    static func shown(sizes: [Int64], limit: Int = 60, minimumShare: Double = 0.002) -> (indices: [Int], rest: Int64) {
        let total = sizes.reduce(0, +)
        let order = sizes.indices.sorted { sizes[$0] > sizes[$1] }
        var indices: [Int] = []
        var rest: Int64 = 0
        for index in order {
            if indices.count < limit, total > 0, Double(sizes[index]) / Double(total) >= minimumShare, sizes[index] > 0 {
                indices.append(index)
            } else {
                rest += sizes[index]
            }
        }
        return (indices, rest)
    }

    /// Files under this size are counted in their folder, not kept one by one.
    static let smallFile: Int64 = 1 << 20
}
