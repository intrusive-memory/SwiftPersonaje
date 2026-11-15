import ArgumentParser
import Foundation
import SwiftReparto
import Testing

@testable import PersonajeCLICore
@testable import SwiftPersonaje

@Suite("personaje cast-discover")
struct CastDiscoverCommandTests {

  private func command(_ arguments: [String]) throws -> CastDiscoverCommand {
    try CastDiscoverCommand.parse(arguments)
  }

  private func castFile(_ project: URL) -> URL {
    project.appendingPathComponent("CAST.md")
  }

  @Test("Finds PROJECT.md above the working directory and reports against CAST.md beside it (SP-8)")
  func locatesProjectFromSubdirectory() async throws {
    let project = try Synthetic.makeProject()
    let nested = project.appendingPathComponent("episodes", isDirectory: true)

    let output = try await command([]).execute(workingDirectory: nested)

    #expect(output.contains("Project: \(project.path)"))
    #expect(output.contains("Would add 6 to CAST.md:"))
    #expect(output.contains("  + ZED (1 line)"))
    #expect(output.contains("  + BOB (3 lines)"))
    #expect(output.contains("Report only: CAST.md not written."))
    // §2: report-only. The Personaje app is the only CAST.md builder.
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("--project takes the directory explicitly")
  func explicitProject() async throws {
    let project = try Synthetic.makeProject()
    let elsewhere = try Synthetic.makeDirectory()
    let output = try await command(["--project", project.path])
      .execute(workingDirectory: elsewhere)
    #expect(output.contains("Project: \(project.path)"))
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("Never writes an existing CAST.md, even when counts and members would change")
  func neverWritesExistingCastFile() async throws {
    let project = try Synthetic.makeProject()
    let handWritten = """
      ---
      type: cast
      schemaVersion: 1
      cast:
      - character: BOB
        voicePrompt: Warm and quick.
        lineCount: 1
      - character: ALICE
        lineCount: 3
      ---

      """
    try Synthetic.write(handWritten, to: castFile(project))

    let output = try await command(["--project", project.path])
      .execute(workingDirectory: project)

    #expect(try Synthetic.read(castFile(project)) == handWritten)
    #expect(output.contains("Would add 4 to CAST.md:"))
    #expect(output.contains("  + BARTENDER (1 line)"))
    #expect(output.contains("Would update 1 line count:"))
    #expect(output.contains("  ~ BOB: 1 -> 3"))
    #expect(!output.contains("~ ALICE"))
    #expect(output.contains("Report only: CAST.md not written."))
  }

  @Test("A CAST.md that is current is reported as such and left alone")
  func currentCastFile() async throws {
    let project = try Synthetic.makeProject()
    // Build CAST.md the way the app does: through the library writer.
    _ = try await CastDiscovery.discover(
      screenplays: Synthetic.episodeURLs(in: project, Synthetic.episodes.map(\.name)),
      castFile: castFile(project))
    let built = try Synthetic.read(castFile(project))

    let output = try await command(["--project", project.path])
      .execute(workingDirectory: project)
    #expect(output.contains("Nothing to change; CAST.md is current (6 members)."))
    #expect(try Synthetic.read(castFile(project)) == built)
  }

  @Test("--dry-run is accepted and changes nothing (SP-7)")
  func dryRun() async throws {
    let project = try Synthetic.makeProject()
    let output = try await command(["--project", project.path, "--dry-run"])
      .execute(workingDirectory: project)
    #expect(output.contains("Would add 6 to CAST.md:"))
    #expect(output.contains("  + COP #1 (1 line)"))
    #expect(output.contains("Report only: CAST.md not written."))
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("--json prints the report, line counts included")
  func json() async throws {
    let project = try Synthetic.makeProject()
    let output = try await command(["--project", project.path, "--json"])
      .execute(workingDirectory: project)
    let report = try JSONDecoder().decode(CastDiscovery.Report.self, from: Data(output.utf8))
    #expect(report.dryRun)
    #expect(!report.wrote)
    #expect(report.added == ["ALICE", "BARTENDER", "BOB", "COP #1", "NARRATOR", "ZED"])
    #expect(report.screenplays.count == 3)
    #expect(
      report.lineCounts.map(\.lineCount) == [3, 1, 3, 1, 1, 1])
    #expect(report.lineCounts.allSatisfy { $0.previous == nil })
    #expect(output.contains("\"lineCounts\""))
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("A comma-separated filePattern names the episode files one by one (§7)")
  func commaSeparatedFilePattern() async throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: "filePattern: \"01-one.fountain, 03-three.fountain\"")
    let opened = try PersonajeProject(directory: project)
    #expect(opened.screenplayPatterns == ["01-one.fountain", "03-three.fountain"])
    #expect(
      opened.screenplayFiles().map(\.lastPathComponent) == ["01-one.fountain", "03-three.fountain"])

    let output = try await command(["--project", project.path, "--json"])
      .execute(workingDirectory: project)
    let report = try JSONDecoder().decode(CastDiscovery.Report.self, from: Data(output.utf8))
    #expect(report.discovered == ["ALICE", "BOB", "COP #1", "NARRATOR"])
  }

  @Test("No PROJECT.md anywhere above is an error")
  func noProject() async throws {
    let empty = try Synthetic.makeDirectory()
    await #expect(throws: (any Error).self) {
      _ = try await command(["--project", empty.path]).execute(workingDirectory: empty)
    }
  }

  @Test("No matching screenplays is an error, and nothing is written")
  func noScreenplays() async throws {
    let project = try Synthetic.makeProject(frontMatterExtra: "filePattern: \"*.fdx\"")
    await #expect(throws: ValidationError.self) {
      _ = try await command(["--project", project.path]).execute(workingDirectory: project)
    }
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("A legacy cast: block with no CAST.md stops discovery until it is imported")
  func legacyCastBlockRefused() async throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: """
        cast:
          - character: BOB
            voicePrompt: Warm.
        """)
    await #expect(throws: ValidationError.self) {
      _ = try await command(["--project", project.path]).execute(workingDirectory: project)
    }
    #expect(!FileManager.default.fileExists(atPath: castFile(project).path))
  }

  @Test("The root command lists cast-discover")
  func rootCommand() throws {
    #expect(try PersonajeCommand.parseAsRoot(["cast-discover"]) is CastDiscoverCommand)
    #expect(
      try PersonajeCommand.parseAsRoot(["cast-discover", "--dry-run"]) is CastDiscoverCommand)
  }
}
