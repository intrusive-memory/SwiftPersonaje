import Evaluations
import Foundation
import PersonajeEvalKit
import SwiftPersonaje
import Testing

/// One sample per character fixture. The fixture rides along on the sample;
/// the framework's `expected` value is unused, because the gold data isn't a
/// pipeline run.
struct CharacterSample: SampleProtocol {
  let fixture: CharacterFixture

  var input: String { fixture.member }
  var expected: CharacterSummaryRun? { nil }
}

/// Records each run and its scores as the framework produces them, for the
/// JSON report and the threshold checks.
actor RunLog {
  private(set) var runs: [CharacterSummaryRun] = []
  private(set) var scores: [CharacterScores] = []

  func record(_ run: CharacterSummaryRun, _ score: CharacterScores) {
    runs.append(run)
    scores.append(score)
  }
}

/// The Evaluations framework's view of the suite: a dataset of characters,
/// a subject (one pipeline run each), and a metric per evaluator.
struct CharacterSummaryEvaluation: Evaluation {
  let samples: [CharacterSample]
  let corpus: EvidenceCorpus
  let configuration: EvalConfiguration
  let log: RunLog

  var name: String { "character-summaries" }

  var dataset: ArrayLoader<CharacterSample> { ArrayLoader(samples: samples) }

  func subject(from sample: CharacterSample) async throws -> ModelSubject<CharacterSummaryRun> {
    let run: CharacterSummaryRun
    do {
      let pipeline = try await BaselinePipeline.make(
        corpus: corpus, member: sample.input, configuration: configuration)
      run = try await pipeline.run(for: sample.input)
    } catch {
      // The framework counts the failure but drops the error; say what it was.
      print("\(sample.input): run failed: \(error)")
      throw error
    }
    await log.record(
      run, EvalScoring.score(run, against: sample.fixture, verifier: QuoteVerifier(corpus: corpus)))
    return ModelSubject(value: run)
  }

  static let quoteRate = Metric("quote-verification-rate")
  static let precision = Metric("precision")
  static let recall = Metric("recall")
  static let hallucinations = Metric("no-hallucinations")
  static let traceability = Metric("summary-traceability")

  func scores(_ sample: CharacterSample, _ subject: ModelSubject<CharacterSummaryRun>)
    -> CharacterScores
  {
    EvalScoring.score(
      subject.value, against: sample.fixture, verifier: QuoteVerifier(corpus: corpus))
  }

  static func scored(_ metric: Metric, _ value: Double?, _ why: String) -> Metric {
    value.map { metric.scoring($0) } ?? metric.ignore(rationale: why)
  }

  var evaluators: [any EvaluatorProtocol<CharacterSample, ModelSubject<CharacterSummaryRun>>] {
    Evaluator<CharacterSample> { sample, subject in
      Self.scored(Self.quoteRate, scores(sample, subject).quoteVerificationRate, "no facts")
    }
    Evaluator<CharacterSample> { sample, subject in
      Self.scored(Self.precision, scores(sample, subject).precision, "fixture not filled in")
    }
    Evaluator<CharacterSample> { sample, subject in
      Self.scored(Self.recall, scores(sample, subject).recall, "fixture not filled in")
    }
    Evaluator<CharacterSample> { sample, subject in
      guard let made = scores(sample, subject).hallucinations else {
        return Self.hallucinations.ignore(rationale: "fixture not filled in")
      }
      return made.isEmpty
        ? Self.hallucinations.passing()
        : Self.hallucinations.failing(rationale: made.joined(separator: ", "))
    }
    Evaluator<CharacterSample> { sample, subject in
      Self.scored(Self.traceability, scores(sample, subject).summaryTraceability, "no summary")
    }
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    aggregator.computeMean(of: Self.quoteRate)
    aggregator.computeMean(of: Self.precision)
    aggregator.computeMean(of: Self.recall)
    aggregator.computeMean(of: Self.traceability)
  }
}

@Suite(
  "Character summaries, model-backed (make test-eval)",
  .enabled(if: EvalGate.isEnabled, Comment(rawValue: EvalGate.reason)),
  .timeLimit(.minutes(60)))
struct CharacterSummaryEvaluationTests {

  @Test("Every character: facts, quotes, summary, scored against the hand-written fixtures")
  func evaluateCharacterSummaries() async throws {
    let configuration = try EvalConfiguration.fromEnvironment()
    let fixtures = try GoldFixtures.load(from: configuration.fixtures)
    let corpus = try await EvidenceCorpus.load(screenplays: configuration.episodes())
    let log = RunLog()

    let evaluation = CharacterSummaryEvaluation(
      samples: fixtures.map(CharacterSample.init), corpus: corpus,
      configuration: configuration, log: log)
    let result = try await evaluation.run(info: [
      "model": BaselinePipeline.describe(configuration.model),
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
    ])

    let report = EvalReport(
      model: BaselinePipeline.describe(configuration.model), project: configuration.project.lastPathComponent,
      scores: await log.scores, runs: await log.runs)
    let reportURL = try report.write(to: configuration.reports)
    let frameworkURL = try result.saveJSON(
      to: configuration.reports, includeReportMetadata: true)

    print(report.table)
    print(result.groupedSummary)
    print("Report: \(reportURL.path)\nEvaluations result: \(frameworkURL.path)")

    #expect(!result.errors.hasFailures, "inference or evaluator errors: \(result.errors)")
    #expect(report.scores.count == fixtures.count)
    for failure in report.thresholdFailures {
      Issue.record(
        "\(failure). Expected until the real summarizer replaces the baseline; see EvalThresholds."
      )
    }
  }
}
