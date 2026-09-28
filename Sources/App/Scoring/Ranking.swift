import Foundation

enum Ranking {
  /// Competition ranking: equal scores share the same rank (1, 2, 2, 4).
  static func competitionRanks<T>(
    _ rows: [T],
    score: (T) -> Int
  ) -> [(rank: Int32, row: T)] {
    guard !rows.isEmpty else { return [] }
    var result: [(rank: Int32, row: T)] = []
    var index = 0
    var currentRank: Int32 = 1
    var previousScore: Int?
    for row in rows {
      let value = score(row)
      if let previousScore, value != previousScore {
        currentRank = Int32(index + 1)
      } else if previousScore == nil {
        currentRank = 1
      }
      result.append((currentRank, row))
      previousScore = value
      index += 1
    }
    return result
  }
}
