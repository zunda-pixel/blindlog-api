import Foundation

enum RatingCalculator {
  static let kFactor = 32
  static let maxAbsDelta = 50

  static func delta(performance: Double, fieldAverage: Double) -> Int {
    let raw = Double(kFactor) * (performance - fieldAverage)
    let rounded = Int(raw.rounded())
    return min(maxAbsDelta, max(-maxAbsDelta, rounded))
  }
}
