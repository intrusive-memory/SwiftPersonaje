import Foundation
import SwiftCompartido
import SwiftReparto
import Testing

@testable import SwiftPersonaje

@Suite("Cast discovery writer (§7.1)")
struct CastDiscoveryTests {

  // MARK: - RP-P9, RP-P13: one screenplay

  @Test("One screenplay: every speaking character, canonical, character and lineCount only")
  func oneScreenplay() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, ["01-one.fountain"]),
      castFile: cast)

    #expect(report.castFileWasMissing)
    #expect(report.wrote)
    #expect(report.existingCount == 0)
    #expect(report.added == ["ALICE", "BOB", "COP #1"])
    #expect(report.totalCount == 3)

    let document = try CastMarkdownParser().parse(fileURL: cast)
    // RP-P10, RP-P13: character and lineCount, nothing else. `BOB (CONT'D)`
    // and `ALICE (V.O.)` are cues for BOB and ALICE.
    #expect(
      document.cast == [
        CastMember(character: "ALICE", lineCount: 1),
        CastMember(character: "BOB", lineCount: 2),
        CastMember(character: "COP #1", lineCount: 1),
      ])
    let text = try Synthetic.read(cast)
    #expect(text.contains("lineCount: 2"))
    #expect(!text.contains("wordCount"))
    #expect(!text.contains("scene"))
  }

  // MARK: - RP-P10: line counts

  @Test("Counts are character cues summed across episodes, V.O. and CONT'D included")
  func countsAcrossEpisodes() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast)

    let expected: [String: Int] = [
      // ALICE (V.O.) in one, ALICE in two and three.
      "ALICE": 3,
      // Only in episode two.
      "BARTENDER": 1,
      // BOB and BOB (CONT'D) in one, BOB in two.
      "BOB": 3,
      "COP #1": 1,
      "NARRATOR": 1,
      "ZED": 1,
    ]
    let document = try CastMarkdownParser().parse(fileURL: cast)
    #expect(
      Dictionary(uniqueKeysWithValues: document.cast.map { ($0.character, $0.lineCount) })
        == expected.mapValues { Optional($0) })

    // The report carries every count, old (none) and new, in roster order.
    #expect(report.lineCounts.map(\.character) == document.cast.map(\.character))
    #expect(
      report.lineCounts.allSatisfy { $0.previous == nil && $0.lineCount == expected[$0.character] })
    #expect(report.changedLineCounts.count == 6)
    #expect(report.updatedLineCounts.isEmpty)
  }

  /// Every discovered member present, with stale counts; one member discovery
  /// never finds, with a count of its own; a castVersion the app wrote.
  static let staleCounts = """
    ---
    type: cast
    schemaVersion: 1
    castVersion: 4
    cast:
    - character: ZED
      actor: Pat Example
      voicePrompt: A dry, unhurried baritone.
      lineCount: 1
      bio: Runs the bar after hours.
    - character: Alice
      language: en
      lineCount: 1
    - character: BARTENDER
      lineCount: 1
    - character: BOB
      voicePrompt: Warm and quick.
      lineCount: 1
    - character: "COP #1"
      lineCount: 1
    - character: NARRATOR
      lineCount: 1
    - character: THE STRANGER
      lineCount: 9
      bio: Never named on screen.
    ---

    Hand-written notes stay here.

    """

  @Test("A run that adds nobody but changes a count writes; existing counts are replaced")
  func countOnlyChangeWrites() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    try Synthetic.write(Self.staleCounts, to: cast)
    let before = try CastMarkdownParser().parse(fileURL: cast)

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast)

    #expect(report.added.isEmpty)
    #expect(report.wrote)
    #expect(
      report.updatedLineCounts == [
        CastDiscovery.LineCount(character: "Alice", lineCount: 3, previous: 1),
        CastDiscovery.LineCount(character: "BOB", lineCount: 3, previous: 1),
      ])
    #expect(report.changedLineCounts == report.updatedLineCounts)
    // Unchanged counts are still reported, old beside new.
    #expect(
      report.lineCounts.first { $0.character == "ZED" }
        == CastDiscovery.LineCount(character: "ZED", lineCount: 1, previous: 1))
    #expect(!report.lineCounts.contains { $0.character == "THE STRANGER" })

    let after = try CastMarkdownParser().parse(fileURL: cast)
    // Nobody moves; nothing a person wrote changes; castVersion and the body
    // are carried as found.
    #expect(after.cast.map(\.character) == before.cast.map(\.character))
    #expect(after.castVersion == 4)
    #expect(after.body == before.body)
    for (old, new) in zip(before.cast, after.cast) {
      var expected = old
      expected.lineCount = new.lineCount
      #expect(new == expected)
    }
    let counts = Dictionary(uniqueKeysWithValues: after.cast.map { ($0.character, $0.lineCount) })
    #expect(counts["Alice"] == 3)
    #expect(counts["BOB"] == 3)
    #expect(counts["ZED"] == 1)
    // Not discovered: keeps its count.
    #expect(counts["THE STRANGER"] == 9)

    // Nothing changes on the next run, so nothing is written.
    let written = try Synthetic.read(cast)
    let again = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast)
    #expect(!again.wrote)
    #expect(again.changedLineCounts.isEmpty)
    #expect(try Synthetic.read(cast) == written)
  }

  @Test("Dry run reports count changes and leaves the bytes alone")
  func dryRunReportsCountChanges() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    try Synthetic.write(Self.staleCounts, to: cast)

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast, dryRun: true)

    #expect(!report.wrote)
    #expect(report.updatedLineCounts.map(\.character) == ["Alice", "BOB"])
    #expect(try Synthetic.read(cast) == Self.staleCounts)
  }

  @Test("A character who never speaks is not a member")
  func silentCharactersAreSkipped() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, ["03-three.fountain"]),
      castFile: cast)
    #expect(report.added == ["ALICE", "NARRATOR"])
  }

  // MARK: - RP-P11: all at once versus repeated merges

  @Test("Every episode at once and one episode per run, in any order, give the same roster")
  func allAtOnceEqualsRepeatedMerges() async throws {
    let names = Synthetic.episodes.map(\.name)

    let allAtOnce = try Synthetic.makeProject()
    let allCast = allAtOnce.appendingPathComponent("CAST.md")
    _ = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: allAtOnce, names), castFile: allCast)
    let expected = try CastMarkdownParser().parse(fileURL: allCast).cast.map(\.character)
    #expect(expected == ["ALICE", "BARTENDER", "BOB", "COP #1", "NARRATOR", "ZED"])

    let orders: [[String]] = [
      names,
      names.reversed(),
      [names[1], names[2], names[0]],
    ]
    for order in orders {
      let project = try Synthetic.makeProject()
      let cast = project.appendingPathComponent("CAST.md")
      for name in order {
        _ = try await CastDiscovery.discover(
          screenplays: Synthetic.episodeURLs(in: project, [name]), castFile: cast)
      }
      // Same members in the same order. Counts reflect the store each run
      // read (one episode here), so only the roster is compared.
      #expect(
        try CastMarkdownParser().parse(fileURL: cast).cast.map(\.character) == expected,
        "order \(order)")
    }
  }

  @Test("Re-running over the same screenplays adds nothing and leaves the bytes alone")
  func rerunIsANoOp() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    let urls = Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name))
    _ = try await CastDiscovery.discover(screenplays: urls, castFile: cast)
    let before = try Synthetic.read(cast)

    let again = try await CastDiscovery.discover(screenplays: urls, castFile: cast)
    #expect(again.added.isEmpty)
    #expect(!again.wrote)
    #expect(try Synthetic.read(cast) == before)
  }

  // MARK: - RP-P10, RP-P14: hand-written CAST.md

  static let handWritten = """
    ---
    type: cast
    schemaVersion: 1
    cast:
    - character: ZED
      actor: Pat Example
      gender: NB
      voicePrompt: A dry, unhurried baritone.
      voices:
        voxalta:
        - voices/ZED.vox
      bio: Runs the bar after hours.
    - character: BOB
      voicePrompt: Warm and quick.
    - character: Alice
      language: en
    - character: THE STRANGER
      bio: Never named on screen.
    ---

    Hand-written notes stay here.

    """

  @Test("Hand-written members keep every field and their order; new names slot in")
  func preservesHandWrittenFields() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    try Synthetic.write(Self.handWritten, to: cast)
    let before = try CastMarkdownParser().parse(fileURL: cast)

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast)

    #expect(!report.castFileWasMissing)
    #expect(report.existingCount == 4)
    // `Alice` already exists under a different spelling of the same name.
    #expect(Set(report.added) == ["BARTENDER", "COP #1", "NARRATOR"])

    let after = try CastMarkdownParser().parse(fileURL: cast)
    #expect(after.body == before.body)

    // Every original member survives in its original order, unchanged except
    // for the derived lineCount.
    let originals = after.cast.filter { member in
      before.cast.contains { $0.character == member.character }
    }
    #expect(
      originals.map { member -> CastMember in
        var stripped = member
        stripped.lineCount = nil
        return stripped
      } == before.cast)
    let counts = Dictionary(uniqueKeysWithValues: after.cast.map { ($0.character, $0.lineCount) })
    #expect(counts["ZED"] == 1)
    #expect(counts["BOB"] == 3)
    #expect(counts["Alice"] == 3)
    // Added by hand and never discovered: "not counted yet".
    #expect(counts["THE STRANGER"] == .some(nil))

    // RP-P14: THE STRANGER is not joined to anyone; Alice keeps its spelling.
    #expect(after.cast.filter { $0.character.uppercased() == "ALICE" }.count == 1)
    #expect(after.cast.contains { $0.character == "THE STRANGER" })

    let zed = try #require(after.cast.first { $0.character == "ZED" })
    #expect(zed.actor == "Pat Example")
    #expect(zed.voicePrompt == "A dry, unhurried baritone.")
    #expect(zed.voices["voxalta"] == ["voices/ZED.vox"])
    #expect(zed[extra: "bio"] != nil)

    // Insertion rule: each new name goes before the first member that sorts
    // after it.
    #expect(
      after.cast.map(\.character)
        == ["BARTENDER", "COP #1", "NARRATOR", "ZED", "BOB", "Alice", "THE STRANGER"])
  }

  // MARK: - SP-7: dry run

  @Test("Dry run on a project without CAST.md creates nothing")
  func dryRunCreatesNothing() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast, dryRun: true)

    #expect(report.dryRun)
    #expect(!report.wrote)
    #expect(report.added == ["ALICE", "BARTENDER", "BOB", "COP #1", "NARRATOR", "ZED"])
    #expect(!FileManager.default.fileExists(atPath: cast.path))
  }

  @Test("Dry run on an existing CAST.md leaves its bytes untouched")
  func dryRunLeavesExistingFileAlone() async throws {
    let project = try Synthetic.makeProject()
    let cast = project.appendingPathComponent("CAST.md")
    try Synthetic.write(Self.handWritten, to: cast)

    let report = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: cast, dryRun: true)

    #expect(!report.wrote)
    #expect(!report.added.isEmpty)
    #expect(try Synthetic.read(cast) == Self.handWritten)
  }

  // MARK: - Mapping and ordering units

  private static func info(_ name: String, lines: Int = 7) -> StoreCharacterInfo {
    StoreCharacterInfo(
      name: name, lineCount: lines, wordCount: 42, sceneIds: [], documents: [], firstLine: nil)
  }

  @Test("Raw names that canonicalize to one member sum their counts")
  func mappingSumsCounts() {
    let collection = CharacterCollectionResult(characters: [
      "BOB": Self.info("BOB", lines: 5),
      "@BOB": Self.info("@BOB", lines: 2),
      "bob": Self.info("bob", lines: 1),
      "ALICE": Self.info("ALICE", lines: 4),
      "AL/BERT": Self.info("AL/BERT", lines: 3),
    ])
    let found = CastDiscovery.discoveredMembers(from: collection)
    #expect(
      found.members == [
        CastMember(character: "ALICE", lineCount: 4),
        CastMember(character: "BOB", lineCount: 8),
      ])
  }

  @Test("Names are canonicalized and de-duplicated; invalid names are reported, not rewritten")
  func mappingCanonicalizesAndRejects() {
    let collection = CharacterCollectionResult(characters: [
      "@BOB": Self.info("@BOB"),
      "BOB": Self.info("BOB"),
      "dr. o'neill": Self.info("dr. o'neill"),
      "AL/BERT": Self.info("AL/BERT"),
    ])
    let found = CastDiscovery.discoveredMembers(from: collection)
    #expect(found.members.map(\.character) == ["BOB", "DR. O'NEILL"])
    #expect(found.rejected.map(\.name) == ["AL/BERT"])
  }

  @Test("Placing new members does not depend on the order they arrive in")
  func mergeIsOrderIndependent() {
    let base = ["MILO", "Cass", "ADA"].map { CastMember(character: $0) }
    let batches: [[String]] = [["BEA", "ZOE"], ["AARON", "NED"], ["CASS", "DAN"]]

    func run(_ order: [[String]]) -> [String] {
      var roster = base
      for batch in order {
        roster = CastDiscovery.merge(batch.map { CastMember(character: $0) }, into: roster).cast
      }
      return roster.map(\.character)
    }

    let oneShot = CastDiscovery.merge(
      batches.flatMap { $0 }.sorted().map { CastMember(character: $0) }, into: base
    ).cast.map(\.character)
    #expect(run(batches) == oneShot)
    #expect(run(batches.reversed()) == oneShot)
    #expect(run([batches[2], batches[0], batches[1]]) == oneShot)
    // Base order is kept; `CASS` matches `Cass`.
    #expect(oneShot.filter { ["MILO", "Cass", "ADA"].contains($0) } == ["MILO", "Cass", "ADA"])
    #expect(!oneShot.contains("CASS"))
  }
}
