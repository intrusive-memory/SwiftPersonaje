import Foundation
import SwiftPersonaje

/// One evaluation run, written as JSON so runs can be compared over time,
/// across OS updates and models.
public struct EvalReport: Sendable, Codable {
  public let date: Date
  /// `ProcessInfo.operatingSystemVersionString`, e.g. "Version 27.2 (Build 27C52)":
  /// the on-device model changes with the OS.
  public let operatingSystem: String
  public let model: String
  public let project: String
  public let scores: [CharacterScores]
  public let thresholdFailures: [String]
  /// Every run in full: chunks, facts, dropped facts, summaries.
  public let runs: [CharacterSummaryRun]

  public init(
    date: Date = Date(), model: String, project: String, scores: [CharacterScores],
    runs: [CharacterSummaryRun]
  ) {
    self.date = date
    self.operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    self.model = model
    self.project = project
    self.scores = scores
    self.thresholdFailures = scores.flatMap(EvalThresholds.failures)
    self.runs = runs
  }

  /// Writes `<directory>/character-summaries-<date>.json` and returns its URL.
  public func write(to directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter.string(
      from: date, timeZone: .gmt, formatOptions: [.withYear, .withMonth, .withDay, .withTime])
    let url = directory.appendingPathComponent("character-summaries-\(stamp).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(self).write(to: url)
    return url
  }

  /// The per-character table printed at the end of a run.
  public var table: String {
    func cell(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "—" }
    var lines = [
      "Character summaries — \(model) — \(operatingSystem)",
      "character  fixture  chunks  failed  facts  verified  quote-rate  precision  recall  halluc.  traceable  gold-cov.",
    ]
    for s in scores {
      lines.append(
        [
          s.member.padding(toLength: 9, withPad: " ", startingAt: 0),
          (s.fixtureComplete ? "ready" : "TODO").padding(toLength: 7, withPad: " ", startingAt: 0),
          String(s.chunks).padding(toLength: 6, withPad: " ", startingAt: 0),
          String(s.chunkFailures).padding(toLength: 6, withPad: " ", startingAt: 0),
          String(s.extractedFacts).padding(toLength: 5, withPad: " ", startingAt: 0),
          String(s.verifiedFacts).padding(toLength: 8, withPad: " ", startingAt: 0),
          cell(s.quoteVerificationRate).padding(toLength: 10, withPad: " ", startingAt: 0),
          cell(s.precision).padding(toLength: 9, withPad: " ", startingAt: 0),
          cell(s.recall).padding(toLength: 6, withPad: " ", startingAt: 0),
          (s.hallucinations.map { String($0.count) } ?? "—").padding(
            toLength: 7, withPad: " ", startingAt: 0),
          cell(s.summaryTraceability).padding(toLength: 9, withPad: " ", startingAt: 0),
          cell(s.goldSummaryCoverage),
        ].joined(separator: "  "))
    }
    if scores.contains(where: { !$0.fixtureComplete }) {
      lines.append(
        "TODO: that fixture isn't filled in; precision, recall and hallucinations aren't scored.")
    }
    if !thresholdFailures.isEmpty {
      lines.append("Below the bars (EvalThresholds; expected while the baseline stands in):")
      lines += thresholdFailures.map { "  - \($0)" }
    }
    return lines.joined(separator: "\n")
  }
}
