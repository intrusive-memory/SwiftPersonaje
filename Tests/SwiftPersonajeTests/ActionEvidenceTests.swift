import Foundation
import Testing

@testable import SwiftPersonaje

/// VE-2, VE-3, VE-4 against the synthetic evidence fixture
/// (`Tests/Fixtures/evidence-project/`, CC0). Expected values are copied from
/// its `EXPECTED.md`, cases (a), (b), (c), (d), (h) and (i).
@Suite("Action evidence: introductions, name variants, group statements (VE-2, VE-3, VE-4)")
struct ActionEvidenceTests {

  static let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/evidence-project", isDirectory: true)

  static let quay = "01-the-quay.fountain"
  static let lamp = "02-the-lamp.fountain"

  static var episodes: [URL] {
    [quay, lamp].map {
      fixture.appendingPathComponent("episodes", isDirectory: true).appendingPathComponent($0)
    }
  }

  static let boysLine =
    "PIP, NED and TOBY, three boys of about twelve, race each other down to the waterline."
  static let theyEach = "They each speak with a thick coastal accent."

  /// An item's source, for comparing against EXPECTED.md.
  struct Source: Equatable, CustomStringConvertible {
    let kind: EvidenceItem.Kind
    let episode: String
    let line: Int
    let scene: String?
    let text: String

    init(
      _ kind: EvidenceItem.Kind, _ episode: String, _ line: Int, _ scene: String?, _ text: String
    ) {
      self.kind = kind
      self.episode = episode
      self.line = line
      self.scene = scene
      self.text = text
    }

    init(_ item: EvidenceItem) {
      self.init(item.kind, item.episode, item.line, item.sceneNumber, item.text)
    }

    var description: String { "\(kind) \(episode):\(line) [\(scene ?? "-")] \(text)" }
  }

  // MARK: - VE-2, VE-3: case (a)

  @Test("The constable's introduction is found under the short cue CONSTABLE (case a)")
  func introductionFoundUnderShortCue() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: "CONSTABLE")

    let expected = Source(
      .introduction, Self.quay, 16, "1",
      #"CONSTABLE HAROLD "HAL" BRISK, 40's, rain cape buttoned to the chin, strides the length of the quay. All six-foot-five of him."#
    )
    let introductions = evidence.introductions.map(Source.init)
    #expect(introductions == [expected])

    let item = try #require(evidence.introductions.first)
    #expect(item.matchedName == #"CONSTABLE HAROLD "HAL" BRISK"#)
    #expect(item.cue == nil)
    let inItems = evidence.items.contains(item)
    #expect(inItems)
  }

  // MARK: - VE-2: cases (c), (h), (i)

  @Test(
    "Each introduction has its episode, line, scene and exact text (cases c, h, i)",
    arguments: [
      (
        "MARA",
        ActionEvidenceTests.Source(
          .introduction, ActionEvidenceTests.quay, 31, "2",
          "MARA OKAFOR (20's BLACK, CLOSE-CROPPED HAIR) counts coins into a ledger, lips moving.")
      ),
      (
        "WICK",
        ActionEvidenceTests.Source(
          .introduction, ActionEvidenceTests.quay, 77, "4",
          "WICK, 60's, the lighthouse keeper, wiry and salt-bleached, stirs a pot of something grey."
        )
      ),
      (
        "ODILE",
        ActionEvidenceTests.Source(
          .introduction, ActionEvidenceTests.lamp, 12, "0A",
          "ODILE VANCE, 50's, the harbourmaster, sharp-eyed, speaks with a clipped Northern Highland accent."
        )
      ),
    ])
  func introductionHasSource(member: String, expected: Source) async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: member)
    #expect(evidence.introductions.map(Source.init) == [expected])
  }

  // MARK: - VE-4: case (b)

  @Test("\"They each speak…\" counts for each boy who speaks in scene 3 (case b)")
  func groupStatementCountsForEachSpeaker() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let group = Source(.groupStatement, Self.quay, 51, "3", Self.theyEach)
    let introduction = Source(.introduction, Self.quay, 49, "3", Self.boysLine)

    for boy in ["PIP", "NED", "TOBY"] {
      let evidence = try await corpus.evidence(for: boy)
      let sources = evidence.items.map(Source.init)
      let hasGroup = sources.contains(group)
      #expect(hasGroup, "\(boy): \(sources)")
      // The line naming all three is each boy's introduction.
      let hasIntroduction = sources.contains(introduction)
      #expect(hasIntroduction, "\(boy): \(sources)")
      #expect(evidence.introductions.first?.matchedName == boy)
      #expect(evidence.groupStatements.first?.matchedName == nil)
    }

    // The constable doesn't speak in scene 3, so the line isn't his.
    let constable = try await corpus.evidence(for: "CONSTABLE")
    let constableHasIt = constable.items.contains { $0.text == Self.theyEach }
    #expect(!constableHasIt)
  }

  // MARK: - VE-2: case (d)

  @Test("A member with no introduction gets dialogue only, and no error (case d)")
  func noIntroductionReturnsDialogueOnly() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    var evidence: CharacterEvidence?
    do {
      evidence = try await corpus.evidence(for: "FERRYMAN")
    } catch {
      Issue.record("evidence(for: FERRYMAN) threw \(error)")
    }
    let items = try #require(evidence).items
    let allDialogue = items.allSatisfy { $0.kind == .dialogue }
    #expect(allDialogue, "\(items.map(Source.init))")
    #expect(
      items.map { "\($0.episode):\($0.line)" } == [
        "\(Self.quay):21", "\(Self.lamp):47", "\(Self.lamp):53",
      ])
  }

  // MARK: - VE-3: case (h)

  @Test("WICKHAM & SONS is not WICK's evidence (case h)")
  func substringCueIsNotMatched() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: "WICK")

    let hasWickham = evidence.items.contains { $0.text.contains("WICKHAM") }
    #expect(!hasWickham)
    let hasLine29 = evidence.items.contains { $0.episode == Self.quay && $0.line == 29 }
    #expect(!hasLine29)
    let introductionLines = evidence.introductions.map(\.line)
    #expect(introductionLines == [77])
  }

  @Test("A capitalised name matches a cue only as whole words (VE-3)")
  func nameVariantsMatchWholeWordsOnly() {
    #expect(
      CapitalisedNames.firstMatch(
        of: "CONSTABLE", in: #"CONSTABLE HAROLD "HAL" BRISK, 40's, strides."#)?
        .written == #"CONSTABLE HAROLD "HAL" BRISK"#)
    #expect(CapitalisedNames.firstMatch(of: "CONSTABLE", in: "CONSTABLEWICK waves.") == nil)
    #expect(CapitalisedNames.firstMatch(of: "WICK", in: "A plaque reads WICKHAM & SONS.") == nil)
    #expect(
      CapitalisedNames.firstMatch(of: "BRISK", in: #"CONSTABLE HAROLD "HAL" BRISK nods."#) != nil)
    #expect(
      CapitalisedNames.firstMatch(of: "HAROLD BRISK", in: #"HAROLD "HAL" BRISK nods."#) == nil)
    #expect(CapitalisedNames.firstMatch(of: "CONSTABLE", in: "The CONSTABLE'S cape drips.") != nil)
    #expect(CapitalisedNames.firstMatch(of: "MARA", in: "Mara counts coins.") == nil)
    #expect(CapitalisedNames.firstMatch(of: "MR. SMITH", in: "MR. SMITH, 50's, sits.") != nil)
    let names = CapitalisedNames.names(in: Self.boysLine).map(\.written)
    #expect(names == ["PIP", "NED", "TOBY"])
  }

  @Test("The pattern table reads ages, ethnicity, build, voice and groups")
  func patternTableCategories() {
    #expect(
      IntroductionPatterns.categories(matching: "MARA OKAFOR (20's BLACK, CLOSE-CROPPED HAIR)")
        == [.age, .ethnicity])
    #expect(
      IntroductionPatterns.categories(
        matching: "WICK, 60's, the lighthouse keeper, wiry and salt-bleached") == [.age, .build])
    #expect(IntroductionPatterns.categories(matching: "All six-foot-five of him.") == [.build])
    #expect(IntroductionPatterns.categories(matching: Self.theyEach) == [.voice, .groupReference])
    #expect(IntroductionPatterns.categories(matching: "three boys of about twelve") == [.age])
    #expect(IntroductionPatterns.categories(matching: "Gulls wheel over a grey harbour.").isEmpty)
    let refersToGroup = IntroductionPatterns.refersToGroup("The boys wade in up to their knees.")
    #expect(!refersToGroup)
  }
}
