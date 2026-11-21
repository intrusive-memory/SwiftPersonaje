import Foundation
import Testing

@testable import SwiftPersonaje

@Suite("Quote verification: a fact's quote is in the scene it cites")
struct QuoteVerifierTests {

  static let lamp = SummarySynthetic.lamp
  static let letter = SummarySynthetic.letter

  func verifier() async throws -> QuoteVerifier {
    QuoteVerifier(corpus: try await SummarySynthetic.corpus())
  }

  func verify(_ quote: String, _ episode: String, _ scene: String?) async throws -> QuoteVerdict {
    try await verifier().verify(quote, at: SummarySynthetic.citation(episode, scene))
  }

  // MARK: - Scenes

  @Test("The corpus's scenes carry SN-1 numbers, sluglines and file lines")
  func scenesAreNumbered() async throws {
    let scenes = try await SummarySynthetic.corpus().scenes()
    #expect(
      scenes.map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "1"), SummarySynthetic.citation(Self.lamp, "2"),
        SummarySynthetic.citation(Self.lamp, "3"), SummarySynthetic.citation(Self.letter, "1"),
      ])
    #expect(scenes[0].heading == "INT. LIGHTHOUSE - NIGHT")
    #expect(scenes[0].line == 4)
    let wren = try #require(scenes[0].blocks.first { $0.speaker == "WREN" })
    #expect(wren.line == 8)
    #expect(wren.cueLine == "WREN")
    #expect(wren.spoken.count == 2)
  }

  // MARK: - Exact and normalized matches

  @Test("An exact quote verifies, on the line of its block")
  func exactQuote() async throws {
    #expect(try await verify("I count.", Self.lamp, "1") == .verified(line: 16))
  }

  @Test("A quote with straight quotes matches the script's curly ones, and the reverse")
  func curlyAndStraightQuotes() async throws {
    #expect(try await verify("You're imagining things", Self.lamp, "1").isVerified)
    #expect(try await verify("“Nothing for the lighthouse,” she says.", Self.lamp, "3").isVerified)
    #expect(try await verify("\"Nothing for the lighthouse,\" she says.", Self.lamp, "3").isVerified)
  }

  @Test("Single and double quotation marks match each other")
  func singleAndDoubleQuotes() async throws {
    #expect(try await verify("‘Nothing for the lighthouse,’ she says.", Self.lamp, "3").isVerified)
    #expect(try await verify("'Nothing for the lighthouse,' she says.", Self.lamp, "3").isVerified)
    #expect(try await verify("I don’t imagine.", Self.lamp, "1").isVerified)
  }

  @Test("Any dash form matches any other: --, an em dash, an en dash, a spaced hyphen")
  func dashForms() async throws {
    for dash in [" -- ", "—", " — ", "–", " - "] {
      let quote = "three nights running\(dash)and nobody's said a word"
      #expect(try await verify(quote, Self.lamp, "1").isVerified, "dash \(dash)")
    }
    #expect(try await verify("imagining things -- again", Self.lamp, "1").isVerified)
  }

  @Test("Line breaks and runs of whitespace inside dialogue match one space")
  func whitespaceAndLineBreaks() async throws {
    #expect(try await verify("I don't imagine. I count.", Self.lamp, "1").isVerified)
    #expect(try await verify("I don't   imagine.\n\nI count.", Self.lamp, "1").isVerified)
  }

  @Test("Case is ignored: a name in capitals in action matches mixed case")
  func caseIsIgnored() async throws {
    #expect(try await verify("i count.", Self.lamp, "1").isVerified)
    #expect(try await verify("Wren, 60's, oilskin coat", Self.lamp, "1").isVerified)
    #expect(try await verify("letters addressed to Wren", Self.lamp, "3").isVerified)
  }

  @Test("Quotation marks around the whole quote are ignored")
  func surroundingQuotationMarks() async throws {
    #expect(try await verify("\"I count.\"", Self.lamp, "1").isVerified)
    #expect(try await verify("“I count.”", Self.lamp, "1").isVerified)
  }

  // MARK: - Parentheticals and cues

  @Test("A quote may skip a parenthetical inside the speech, or include it")
  func parentheticalInsideSpan() async throws {
    #expect(try await verify("said a word. Not one word.", Self.lamp, "1").isVerified)
    #expect(try await verify("said a word. (beat) Not one word.", Self.lamp, "1").isVerified)
  }

  @Test("A quote that runs across a cue into the next speaker's line is rejected")
  func quoteAcrossCueIsRejected() async throws {
    #expect(!(try await verify("Not one word. OTTO You're imagining", Self.lamp, "1").isVerified))
    #expect(!(try await verify("Not one word. You're imagining", Self.lamp, "1").isVerified))
  }

  @Test("The cue line is not part of the quotable text")
  func cueIsNotQuotable() async throws {
    #expect(!(try await verify("WREN I don't imagine.", Self.lamp, "1").isVerified))
  }

  @Test("Action paragraphs are quotable")
  func actionIsQuotable() async throws {
    #expect(try await verify("oilskin coat, climbs the spiral stair", Self.lamp, "1").isVerified)
  }

  // MARK: - Rejections

  @Test("A close paraphrase is rejected")
  func paraphraseIsRejected() async throws {
    #expect(
      try await verify("The lamp has been dark for three nights", Self.lamp, "1")
        == .notInScene(foundIn: []))
    #expect(!(try await verify("I don't imagine, I count.", Self.lamp, "1").isVerified))
  }

  @Test("A quote cited to the wrong scene is rejected, naming the scene that holds it")
  func wrongSceneIsRejected() async throws {
    #expect(
      try await verify("She counts everything.", Self.lamp, "1")
        == .notInScene(foundIn: [SummarySynthetic.citation(Self.lamp, "2")]))
    #expect(!(try await verify("I count.", Self.letter, "1").isVerified))
  }

  @Test("A citation to a scene or episode that doesn't exist is rejected")
  func missingSceneOrEpisode() async throws {
    #expect(try await verify("I count.", Self.lamp, "9") == .unknownScene)
    #expect(try await verify("I count.", Self.lamp, nil) == .unknownScene)
    #expect(try await verify("I count.", "03-missing.fountain", "1") == .unknownEpisode)
  }

  @Test("A quote must start and end on word boundaries")
  func wordBoundaries() async throws {
    #expect(!(try await verify("ount", Self.lamp, "1").isVerified))
    #expect(!(try await verify("I coun", Self.lamp, "1").isVerified))
  }

  @Test("An empty quote is rejected")
  func emptyQuote() async throws {
    #expect(try await verify("  \"\" ", Self.lamp, "1") == .emptyQuote)
  }

  // MARK: - Facts

  @Test("partition keeps facts whose quotes verify and drops the rest with their verdicts")
  func partitionFacts() async throws {
    let good = CharacterFact(
      id: "f1", statement: "Wren counts.", quote: "I count.",
      citation: SummarySynthetic.citation(Self.lamp, "1"))
    let bad = CharacterFact(
      id: "f2", statement: "Wren imagines.", quote: "I imagine.",
      citation: SummarySynthetic.citation(Self.lamp, "1"))
    let (verified, dropped) = try await verifier().partition([good, bad])
    #expect(verified == [good])
    #expect(dropped.map(\.fact) == [bad])
    #expect(dropped.map(\.verdict) == [.notInScene(foundIn: [])])
  }

  // MARK: - Normalization

  @Test("normalize folds quotes, dashes, ellipses, emphasis and whitespace")
  func normalize() {
    #expect(QuoteText.normalize("It’s “fine” -- really…") == "It\"s \"fine\"—really...")
    #expect(QuoteText.normalize("a  –  b\n\nc") == "a—b c")
    #expect(QuoteText.normalize("*Never* _again_") == "Never again")
    #expect(QuoteText.normalize("six-foot-five") == "six-foot-five")
  }
}
