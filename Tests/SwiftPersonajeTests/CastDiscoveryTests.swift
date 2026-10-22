import Foundation
import SwiftCompartido
import SwiftReparto
import Testing

@testable import SwiftPersonaje

@Suite("Cast discovery writer (§7.1)")
struct CastDiscoveryTests {

  // MARK: - RP-P9, RP-P13: one screenplay

  @Test("One screenplay: every speaking character, canonical, character only")
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
    #expect(document.cast.map(\.character) == ["ALICE", "BOB", "COP #1"])
    for member in document.cast {
      // RP-P13 and "sets only character": nothing else is filled in.
      #expect(member == CastMember(character: member.character))
    }
    let text = try Synthetic.read(cast)
    #expect(!text.contains("lineCount"))
    #expect(!text.contains("wordCount"))
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

  @Test("Every episode at once and one episode per run, in any order, give identical bytes")
  func allAtOnceEqualsRepeatedMerges() async throws {
    let names = Synthetic.episodes.map(\.name)

    let allAtOnce = try Synthetic.makeProject()
    let allCast = allAtOnce.appendingPathComponent("CAST.md")
    _ = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: allAtOnce, names), castFile: allCast)
    let expected = try Synthetic.read(allCast)
    #expect(
      try CastMarkdownParser().parse(fileURL: allCast).cast.map(\.character)
        == ["ALICE", "BARTENDER", "BOB", "COP #1", "NARRATOR", "ZED"])

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
      #expect(try Synthetic.read(cast) == expected, "order \(order)")
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

    // Every original member survives unchanged, in its original order.
    let originals = after.cast.filter { member in
      before.cast.contains { $0.character == member.character }
    }
    #expect(originals == before.cast)

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

  private static func info(_ name: String) -> StoreCharacterInfo {
    StoreCharacterInfo(
      name: name, lineCount: 7, wordCount: 42, sceneIds: [], documents: [], firstLine: nil)
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
