import Foundation
import SwiftCompartido
import Testing

@testable import SwiftPersonaje

/// VE-1, VE-5, VE-8 against the synthetic evidence fixture
/// (`Tests/Fixtures/evidence-project/`, CC0). Expected values are copied from
/// its `EXPECTED.md`.
@Suite("Character evidence: dialogue, windows, sources (VE-1, VE-5, VE-8)")
struct CharacterEvidenceTests {

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

  static let members = [
    "CONSTABLE", "FERRYMAN", "MARA", "NARRATOR", "NED", "ODILE", "PIP", "TOBY", "WICK",
  ]

  // MARK: - Recon U-1

  @Test("SwiftCompartido returns line windows on a fresh parse (recon U-1)")
  func lineWindowsOnFreshParse() async throws {
    let actor = DocumentModelActor(modelContainer: try CastDiscovery.makeContainer())
    for url in Self.episodes {
      _ = try await actor.parseAndSaveDocument(from: url, parseGlosa: false)
    }
    for member in Self.members {
      do {
        let windows = try await actor.fetchLineWindows(for: member, neighbours: 3)
        #expect(!windows.isEmpty, "no windows for \(member)")
        let hasLine = windows.contains { window in window.blocks.contains(where: \.isCharacterLine) }
        #expect(hasLine, "no line block for \(member)")
      } catch DocumentModelActorError.speakerDataMissing(let titles) {
        Issue.record("speakerDataMissing on a fresh parse: \(titles)")
      }
    }
  }

  // MARK: - VE-1

  @Test("The narrator's items keep V.O., O.S. and PRELAP from the raw cue")
  func narratorKeepsCueExtensions() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: "NARRATOR")
    let items = evidence.dialogue

    let extensions = Set(items.flatMap(\.extensions))
    let hasAll = extensions.isSuperset(of: ["V.O.", "O.S.", "PRELAP"])
    #expect(hasAll, "extensions found: \(extensions.sorted())")

    let found = items.map { Placed(episode: $0.episode, line: $0.line, extensions: $0.extensions) }
    #expect(
      found == [
        Placed(episode: Self.quay, line: 12, extensions: ["V.O."]),
        Placed(episode: Self.quay, line: 36, extensions: ["O.S."]),
        Placed(episode: Self.quay, line: 72, extensions: ["PRELAP"]),
        Placed(episode: Self.lamp, line: 40, extensions: ["V.O."]),
        Placed(episode: Self.lamp, line: 76, extensions: ["V.O."]),
      ])

    let first = try #require(items.first)
    #expect(first.cue == "NARRATOR (V.O.)")
    #expect(first.parentheticals == ["(quietly)"])
    #expect(first.text == "(quietly)\nEvery town on this coast keeps one secret. Ours kept two.")
    #expect(first.kind == .dialogue)
  }

  // MARK: - VE-5

  @Test("A window around .MUSIC CONTINUES holds blocks from both sides of it")
  func forcedLineDoesNotCutWindow() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: "TOBY")

    let spanning = evidence.windows.filter { window in
      window.blocks.contains(where: { $0.text == ".MUSIC CONTINUES" })
    }
    #expect(spanning.count == 1)
    let window = try #require(spanning.first)
    #expect(window.episode == Self.quay)
    #expect(window.sceneNumber == "3")
    #expect(window.heading == "EXT. SHINGLE BEACH - AFTERNOON")

    let lines = window.blocks.map(\.line)
    // ±3 blocks around TOBY's line 59, across the forced line at 62.
    #expect(lines == [51, 53, 56, 59, 62, 64, 66])
    let tobyBefore = window.blocks.contains { $0.line == 59 && $0.speaker == "TOBY" && $0.isMemberLine }
    #expect(tobyBefore)
    let actionAfter = window.blocks.contains { $0.line == 64 && $0.speaker == nil }
    #expect(actionAfter)
    let pipAfter = window.blocks.contains { $0.line == 66 && $0.speaker == "PIP" && !$0.isMemberLine }
    #expect(pipAfter)
  }

  @Test("Overlapping windows in one scene merge; windows stay inside their scene")
  func overlappingWindowsMerge() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    let evidence = try await corpus.evidence(for: "NED")
    // NED speaks at lines 56 and 69 of scene 3 (10 blocks, the forced line
    // one of them): ±3 windows share blocks, so they merge into one.
    #expect(evidence.windows.count == 1)
    let window = try #require(evidence.windows.first)
    #expect(window.blocks.map(\.line) == [49, 51, 53, 56, 59, 62, 64, 66, 69, 72])
    let memberLines = window.blocks.filter(\.isMemberLine).map(\.line)
    #expect(memberLines == [56, 69])
  }

  // MARK: - VE-8

  @Test("Every dialogue item carries its episode, cue line and EXPECTED.md scene number")
  func sceneNumbersMatchExpected() async throws {
    let corpus = try await EvidenceCorpus.load(screenplays: Self.episodes)
    var found: [Expected] = []
    for member in Self.members {
      let evidence = try await corpus.evidence(for: member)
      #expect(evidence.member == member)
      for item in evidence.dialogue {
        found.append(
          Expected(episode: item.episode, line: item.line, cue: member, scene: item.sceneNumber))
      }
    }
    #expect(found.count == 31)
    #expect(found.sorted() == Self.expectedDialogue.sorted())
  }

  /// Every dialogue block in EXPECTED.md: episode, cue line, speaker, SN-1.
  static let expectedDialogue: [Expected] = [
    Expected(episode: quay, line: 12, cue: "NARRATOR", scene: "1"),
    Expected(episode: quay, line: 18, cue: "CONSTABLE", scene: "1"),
    Expected(episode: quay, line: 21, cue: "FERRYMAN", scene: "1"),
    Expected(episode: quay, line: 24, cue: "CONSTABLE", scene: "1"),
    Expected(episode: quay, line: 33, cue: "MARA", scene: "2"),
    Expected(episode: quay, line: 36, cue: "NARRATOR", scene: "2"),
    Expected(episode: quay, line: 39, cue: "MARA", scene: "2"),
    Expected(episode: quay, line: 53, cue: "PIP", scene: "3"),
    Expected(episode: quay, line: 56, cue: "NED", scene: "3"),
    Expected(episode: quay, line: 59, cue: "TOBY", scene: "3"),
    Expected(episode: quay, line: 66, cue: "PIP", scene: "3"),
    Expected(episode: quay, line: 69, cue: "NED", scene: "3"),
    Expected(episode: quay, line: 72, cue: "NARRATOR", scene: "3"),
    Expected(episode: quay, line: 79, cue: "WICK", scene: "4"),
    Expected(episode: quay, line: 82, cue: "MARA", scene: "4"),
    Expected(episode: quay, line: 85, cue: "WICK", scene: "4"),
    Expected(episode: lamp, line: 14, cue: "ODILE", scene: "0A"),
    Expected(episode: lamp, line: 17, cue: "CONSTABLE", scene: "0A"),
    Expected(episode: lamp, line: 20, cue: "ODILE", scene: "0A"),
    Expected(episode: lamp, line: 27, cue: "MARA", scene: "1"),
    Expected(episode: lamp, line: 30, cue: "WICK", scene: "1"),
    Expected(episode: lamp, line: 37, cue: "WICK", scene: "1A"),
    Expected(episode: lamp, line: 40, cue: "NARRATOR", scene: "1A"),
    Expected(episode: lamp, line: 47, cue: "FERRYMAN", scene: "2"),
    Expected(episode: lamp, line: 50, cue: "ODILE", scene: "2"),
    Expected(episode: lamp, line: 53, cue: "FERRYMAN", scene: "2"),
    Expected(episode: lamp, line: 66, cue: "PIP", scene: "2B"),
    Expected(episode: lamp, line: 69, cue: "CONSTABLE", scene: "2B"),
    Expected(episode: lamp, line: 76, cue: "NARRATOR", scene: "2A"),
    Expected(episode: lamp, line: 83, cue: "MARA", scene: "3"),
    Expected(episode: lamp, line: 86, cue: "CONSTABLE", scene: "3"),
  ]

  struct Expected: Equatable, Comparable, CustomStringConvertible {
    let episode: String
    let line: Int
    let cue: String
    let scene: String?

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.episode, lhs.line, lhs.cue) < (rhs.episode, rhs.line, rhs.cue)
    }

    var description: String { "\(episode):\(line) \(cue) [\(scene ?? "-")]" }
  }

  struct Placed: Equatable, CustomStringConvertible {
    let episode: String
    let line: Int
    let extensions: [String]

    var description: String { "\(episode):\(line) \(extensions)" }
  }
}
