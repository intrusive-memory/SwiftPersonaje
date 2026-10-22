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

  @Test("Finds PROJECT.md above the working directory and writes CAST.md beside it (SP-8)")
  func locatesProjectFromSubdirectory() async throws {
    let project = try Synthetic.makeProject()
    let nested = project.appendingPathComponent("episodes", isDirectory: true)

    let output = try await command([]).execute(workingDirectory: nested)

    let cast = project.appendingPathComponent("CAST.md")
    #expect(FileManager.default.fileExists(atPath: cast.path))
    #expect(output.contains("Created CAST.md (6 members)."))
    #expect(output.contains("  + ZED"))
  }

  @Test("--project takes the directory explicitly")
  func explicitProject() async throws {
    let project = try Synthetic.makeProject()
    let elsewhere = try Synthetic.makeDirectory()
    _ = try await command(["--project", project.path]).execute(workingDirectory: elsewhere)
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("CAST.md").path))
  }

  @Test("--dry-run prints the members it would add and writes nothing (SP-7)")
  func dryRun() async throws {
    let project = try Synthetic.makeProject()
    let output = try await command(["--project", project.path, "--dry-run"])
      .execute(workingDirectory: project)
    #expect(output.contains("Would add 6 to CAST.md:"))
    #expect(output.contains("  + COP #1"))
    #expect(output.contains("Dry run: nothing written."))
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("CAST.md").path))
  }

  @Test("--json prints the report")
  func json() async throws {
    let project = try Synthetic.makeProject()
    let output = try await command(["--project", project.path, "--json", "--dry-run"])
      .execute(workingDirectory: project)
    let report = try JSONDecoder().decode(CastDiscovery.Report.self, from: Data(output.utf8))
    #expect(report.dryRun)
    #expect(report.added == ["ALICE", "BARTENDER", "BOB", "COP #1", "NARRATOR", "ZED"])
    #expect(report.screenplays.count == 3)
  }

  @Test("A comma-separated filePattern names the episode files one by one (§7)")
  func commaSeparatedFilePattern() async throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: "filePattern: \"01-one.fountain, 03-three.fountain\"")
    let opened = try PersonajeProject(directory: project)
    #expect(opened.screenplayPatterns == ["01-one.fountain", "03-three.fountain"])
    #expect(
      opened.screenplayFiles().map(\.lastPathComponent) == ["01-one.fountain", "03-three.fountain"])

    _ = try await command(["--project", project.path]).execute(workingDirectory: project)
    let cast = try CastMarkdownParser().parse(
      fileURL: project.appendingPathComponent("CAST.md"))
    #expect(cast.cast.map(\.character) == ["ALICE", "BOB", "COP #1", "NARRATOR"])
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
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("CAST.md").path))
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
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("CAST.md").path))
  }

  @Test("The root command lists cast-discover")
  func rootCommand() throws {
    let parsed = try PersonajeCommand.parseAsRoot(["cast-discover", "--dry-run"])
    #expect(parsed is CastDiscoverCommand)
  }
}
