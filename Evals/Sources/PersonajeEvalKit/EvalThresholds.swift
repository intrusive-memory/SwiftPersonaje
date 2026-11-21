import Foundation

/// Every pass bar of the evaluation, in one place.
///
/// They start loose on purpose. Read the numbers the first runs print, then
/// tighten these. `maximumHallucinations` is the exception: it is zero and
/// stays zero.
public enum EvalThresholds {
  public static let quoteVerificationRate = 0.5
  public static let precision = 0.3
  public static let recall = 0.2
  public static let maximumHallucinations = 0
  public static let summaryTraceability = 0.5

  /// The bars `scores` misses, each as a sentence. Metrics that weren't
  /// scored (`nil`) pass.
  public static func failures(_ scores: CharacterScores) -> [String] {
    var result: [String] = []
    func below(_ name: String, _ value: Double?, _ bar: Double) {
      if let value, value < bar {
        result.append(
          "\(scores.member): \(name) \(format(value)) is below \(format(bar))")
      }
    }
    below("quote verification rate", scores.quoteVerificationRate, quoteVerificationRate)
    below("precision", scores.precision, precision)
    below("recall", scores.recall, recall)
    below("summary traceability", scores.summaryTraceability, summaryTraceability)
    if let hallucinations = scores.hallucinations, hallucinations.count > maximumHallucinations {
      result.append(
        "\(scores.member): made must-not-say claims \(hallucinations.joined(separator: ", "))")
    }
    if !scores.invalidGoldFactIDs.isEmpty {
      result.append(
        "\(scores.member): gold facts whose quotes don't verify (fix the fixture): \(scores.invalidGoldFactIDs.joined(separator: ", "))"
      )
    }
    if let failure = scores.summaryFailure {
      result.append("\(scores.member): no summary: \(failure)")
    }
    if scores.extractedFacts == 0 && scores.chunks > 0 {
      result.append("\(scores.member): no facts extracted from \(scores.chunks) chunks")
    }
    return result
  }

  static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
