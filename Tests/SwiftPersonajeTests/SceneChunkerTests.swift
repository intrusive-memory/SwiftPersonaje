import Foundation
import Testing

@testable import SwiftPersonaje

/// Token counts here are whitespace words (``WordCounter``). The letter
/// episode's one scene is 59 words: a 5-word slugline, WREN's 48-word speech
/// (cue included, lines 6–11) and OTTO's 6-word line (lines 13–14).
@Suite("Scene chunking: a character's scenes, cut to fit the model's context")
struct SceneChunkerTests {

  static let lamp = SummarySynthetic.lamp
  static let letter = SummarySynthetic.letter

  /// 100 tokens of context, 50 kept for output, 20 for the prompt: 30 left.
  static let tight = ChunkBudget(contextSize: 100, reservedForOutput: 50, overhead: 20)

  func letterScene() async throws -> SceneSource {
    try #require(
      try await SummarySynthetic.corpus().scenes().first { $0.citation.episode == Self.letter })
  }

  // MARK: - Which scenes

  @Test("Only scenes the character speaks in or is named in are chosen")
  func scenesFeaturingMember() async throws {
    let corpus = try await SummarySynthetic.corpus()
    #expect(
      corpus.scenes(featuring: "WREN").map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "1"),
        SummarySynthetic.citation(Self.lamp, "3"),  // named in action only
        SummarySynthetic.citation(Self.letter, "1"),
      ])
    #expect(
      corpus.scenes(featuring: "OTTO").map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "1"),
        SummarySynthetic.citation(Self.lamp, "2"),  // a V.O. cue
        SummarySynthetic.citation(Self.letter, "1"),
      ])
    #expect(
      corpus.scenes(featuring: "MAGGIE").map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "3")
      ])
    #expect(corpus.scenes(featuring: "NOBODY").isEmpty)
  }

  @Test("A name inside another word doesn't count as appearing")
  func partialNameDoesNotCount() async throws {
    let corpus = try await SummarySynthetic.corpus()
    #expect(corpus.scenes(featuring: "WRE").isEmpty)
  }

  // MARK: - Fitting the budget

  @Test("A scene that fits becomes one chunk holding the whole scene")
  func sceneThatFits() async throws {
    let budget = ChunkBudget(contextSize: 200, reservedForOutput: 100, overhead: 40)
    let chunks = try await SceneChunker(budget: budget, counter: WordCounter())
      .chunks(of: [try await letterScene()])
    #expect(chunks.count == 1)
    let chunk = try #require(chunks.first)
    #expect(chunk.part == 1 && chunk.partCount == 1)
    #expect(chunk.tokenCount == 59)
    #expect((chunk.firstLine, chunk.lastLine) == (6, 14))
    #expect(chunk.text.hasPrefix("INT. LIGHTHOUSE KITCHEN - MORNING\n\nWREN\n"))
  }

  @Test("Every chunk fits the budget and leaves the output's share of the context free")
  func everyChunkFits() async throws {
    let corpus = try await SummarySynthetic.corpus()
    let chunks = try await SceneChunker(budget: Self.tight, counter: WordCounter())
      .chunks(of: corpus.scenes())
    #expect(!chunks.isEmpty)
    for chunk in chunks {
      #expect(chunk.tokenCount <= Self.tight.inputLimit)
      #expect(
        chunk.tokenCount + Self.tight.overhead + Self.tight.reservedForOutput
          <= Self.tight.contextSize)
      #expect(try await WordCounter().tokenCount(for: chunk.text) == chunk.tokenCount)
    }
  }

  // MARK: - Splitting a large scene

  @Test("A scene too large for one chunk is split at line boundaries, citation on every part")
  func largeSceneIsSplit() async throws {
    let scene = try await letterScene()
    let chunks = try await SceneChunker(budget: Self.tight, counter: WordCounter())
      .chunks(of: [scene])

    #expect(chunks.map(\.part) == [1, 2, 3])
    #expect(chunks.allSatisfy { $0.partCount == 3 })
    #expect(chunks.allSatisfy { $0.citation == scene.citation })
    #expect(chunks.map { [$0.firstLine, $0.lastLine] } == [[6, 8], [9, 10], [11, 14]])
    #expect(chunks.map(\.tokenCount) == [25, 26, 22])
  }

  @Test("No line is cut: every line of every chunk is a whole line of the scene")
  func noLineIsCut() async throws {
    let scene = try await letterScene()
    let chunks = try await SceneChunker(budget: Self.tight, counter: WordCounter())
      .chunks(of: [scene])
    let heading = try #require(scene.heading)
    let allowed = Set(scene.blocks.flatMap(\.lines) + [heading, "\(heading) (CONTINUED)"])
    for chunk in chunks {
      for line in chunk.text.split(separator: "\n", omittingEmptySubsequences: true) {
        #expect(allowed.contains(String(line)), "\(line)")
      }
    }
    // Every line of the scene is in some chunk.
    let covered = Set(chunks.flatMap { $0.text.split(separator: "\n").map(String.init) })
    #expect(Set(scene.blocks.flatMap(\.lines)).isSubset(of: covered))
  }

  @Test("Each part of a split speech repeats the cue, and later parts mark the slugline")
  func splitSpeechKeepsCue() async throws {
    let chunks = try await SceneChunker(budget: Self.tight, counter: WordCounter())
      .chunks(of: [try await letterScene()])
    #expect(chunks[0].text.hasPrefix("INT. LIGHTHOUSE KITCHEN - MORNING\n\nWREN\n"))
    for chunk in chunks.dropFirst() {
      #expect(chunk.text.hasPrefix("INT. LIGHTHOUSE KITCHEN - MORNING (CONTINUED)\n\nWREN\n"))
    }
  }

  // MARK: - Budgets that can't work

  @Test("A line larger than the budget is an error naming it, not a cut line")
  func lineTooLarge() async throws {
    let budget = ChunkBudget(contextSize: 100, reservedForOutput: 70, overhead: 20)
    let scene = try await letterScene()
    await #expect(
      throws: SceneChunkerError.lineExceedsBudget(scene.citation, line: 7, tokens: 15, limit: 10)
    ) {
      try await SceneChunker(budget: budget, counter: WordCounter()).chunks(of: [scene])
    }
  }

  @Test("A budget with no room for input is an error")
  func noRoomForInput() async throws {
    let budget = ChunkBudget(contextSize: 100, reservedForOutput: 60, overhead: 40)
    await #expect(throws: SceneChunkerError.noRoomForInput(budget)) {
      try await SceneChunker(budget: budget, counter: WordCounter())
        .chunks(of: [try await letterScene()])
    }
  }
}
