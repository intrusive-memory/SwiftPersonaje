import ArgumentParser
import Foundation
import Testing

@testable import PersonajeCLICore
@testable import SwiftPersonaje

@Suite("personaje evidence (VE-9)")
struct EvidenceCommandTests {

  static let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/evidence-project", isDirectory: true)

  static let members = [
    "CONSTABLE", "FERRYMAN", "MARA", "NARRATOR", "NED", "ODILE", "PIP", "TOBY", "WICK",
  ]

  /// Budget from recon U-2: about 3k tokens.
  static let budget = 12_000

  private func run(_ arguments: [String]) async throws -> EvidenceCommand.RunResult {
    try await EvidenceCommand.parse(arguments + ["--project", Self.fixture.path])
      .execute(workingDirectory: Self.fixture)
  }

  @Test("An unknown character prints `unknown character: <NAME>` on stderr and fails")
  func unknownCharacterFails() async throws {
    let result = try await run(["NOBODY"])
    #expect(result.failed)
    #expect(result.errorOutput == "unknown character: NOBODY")
    #expect(result.output.isEmpty)
  }

  @Test("The name matches case-insensitively and the output uses CAST.md's spelling")
  func matchesIgnoringCase() async throws {
    let result = try await run(["constable", "--json"])
    #expect(!result.failed)
    let report = try JSONDecoder().decode(
      EvidenceCommand.Report.self, from: Data(result.output.utf8))
    #expect(report.member == "CONSTABLE")
    #expect(report.evidence.member == "CONSTABLE")
  }

  @Test("--json is only JSON: member, tier and the evidence")
  func jsonShape() async throws {
    let result = try await run(["CONSTABLE", "--json"])
    #expect(result.errorOutput.isEmpty)
    let object = try JSONSerialization.jsonObject(with: Data(result.output.utf8))
    let dictionary = try #require(object as? [String: Any])
    #expect(dictionary["member"] as? String == "CONSTABLE")
    #expect(dictionary["tier"] as? String != nil)
    let evidence = try #require(dictionary["evidence"] as? [String: Any])
    #expect(evidence["items"] != nil)
    #expect(evidence["windows"] != nil)
  }

  @Test("An explicit CAST.md role decides the tier; without one it is computed")
  func tierUsesRole() async throws {
    let toby = try await run(["TOBY", "--json"])
    let tobyReport = try JSONDecoder().decode(
      EvidenceCommand.Report.self, from: Data(toby.output.utf8))
    #expect(tobyReport.role == "supporting")
    #expect(tobyReport.tier == .major)

    let text = try await run(["TOBY"])
    #expect(text.output.contains("Tier: major (CAST.md role: supporting)"))

    let mara = try await run(["MARA"])
    #expect(mara.output.contains("(computed)"))
  }

  @Test("Text output groups items by kind and quotes each with its episode and scene")
  func textOutput() async throws {
    let result = try await run(["CONSTABLE"])
    #expect(result.output.hasPrefix("CONSTABLE\n"))
    #expect(result.output.contains("Accent:"))
    #expect(result.output.contains("Dialogue ("))
    #expect(result.output.contains("Introductions ("))
    #expect(result.output.contains("Group statements ("))
    #expect(result.output.contains("01-the-quay.fountain sc "))
  }

  @Test("Every fixture member's JSON evidence is at most 12,000 characters (recon U-2)")
  func evidenceFitsBudget() async throws {
    for member in Self.members {
      let result = try await run([member, "--json"])
      #expect(!result.failed, "\(member)")
      #expect(
        result.output.count <= Self.budget,
        "\(member): \(result.output.count) characters")
    }
  }
}
