import ArgumentParser
import Foundation
import Testing

@testable import PersonajeCLICore
@testable import SwiftPersonaje

@Suite("personaje number-scenes")
struct NumberScenesCommandTests {

  private static let names = Synthetic.episodes.map(\.name)
  private static let fixedDate = Date(timeIntervalSince1970: 1_795_003_200)  // 2026-11-18T12:00:00Z

  private func command(_ arguments: [String]) throws -> NumberScenesCommand {
    try NumberScenesCommand.parse(arguments)
  }

  private func episodeData(_ project: URL) throws -> [Data] {
    try Synthetic.episodeURLs(in: project, Self.names).map { try Data(contentsOf: $0) }
  }

  private func gitignore(_ project: URL) -> String? {
    try? String(contentsOf: project.appendingPathComponent(".gitignore"), encoding: .utf8)
  }

  @Test("--dry-run reports the headings and changes no bytes, no backup, no .gitignore")
  func dryRunChangesNoBytes() throws {
    let project = try Synthetic.makeProject()
    let before = try episodeData(project)

    let result = try command(["--project", project.path, "--dry-run"])
      .execute(workingDirectory: project, now: Self.fixedDate)

    let after = try episodeData(project)
    #expect(after == before)
    #expect(result.failureCount == 0)
    #expect(result.output.contains("episodes/01-one.fountain: would number 2 headings"))
    #expect(result.output.contains("  + INT. KITCHEN - DAY #1#"))
    #expect(result.output.contains("  + EXT. STREET - NIGHT #2#"))
    #expect(result.output.contains("Would add .personaje/ to .gitignore."))
    #expect(result.output.contains("nothing written"))
    let personaje = project.appendingPathComponent(".personaje").path
    #expect(!FileManager.default.fileExists(atPath: personaje))
    #expect(gitignore(project) == nil)
  }

  @Test("A run numbers every file, backs each up under a timestamped directory, and leaves the backup equal to the original")
  func runNumbersAndBacksUp() throws {
    let project = try Synthetic.makeProject()
    let before = try episodeData(project)

    let result = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate)

    #expect(result.failureCount == 0)
    let backupDir = project.appendingPathComponent(
      ".personaje/backups/20261118T120000Z", isDirectory: true)
    #expect(result.output.contains("Backups: \(backupDir.path)"))
    #expect(result.output.contains("Added .personaje/ to .gitignore."))

    let urls = Synthetic.episodeURLs(in: project, Self.names)
    for (index, url) in urls.enumerated() {
      let text = try Synthetic.read(url)
      let headings = SceneNumbering.headings(in: text)
      let unnumbered = headings.filter { $0.existingNumber == nil }
      #expect(unnumbered.isEmpty)
      #expect(!headings.isEmpty)
      let backup = backupDir.appendingPathComponent("episodes/\(Self.names[index])")
      #expect(try Data(contentsOf: backup) == before[index])
    }
    #expect(try Synthetic.read(urls[0]).contains("INT. KITCHEN - DAY #1#"))
  }

  @Test("A second run finds nothing to number, writes nothing and makes no new backup")
  func secondRunIsNoOp() throws {
    let project = try Synthetic.makeProject()
    _ = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate)
    let numbered = try episodeData(project)

    let later = Self.fixedDate.addingTimeInterval(3600)
    let result = try command(["--project", project.path])
      .execute(workingDirectory: project, now: later)

    #expect(try episodeData(project) == numbered)
    #expect(result.failureCount == 0)
    #expect(result.output.contains("Nothing to number."))
    let laterBackup = project.appendingPathComponent(".personaje/backups/20261118T130000Z").path
    #expect(!FileManager.default.fileExists(atPath: laterBackup))
  }

  @Test("--json prints per-file counts and headings")
  func jsonOutput() throws {
    let project = try Synthetic.makeProject()
    let result = try command(["--project", project.path, "--json", "--dry-run"])
      .execute(workingDirectory: project, now: Self.fixedDate)
    let data = Data(result.output.utf8)
    let report = try JSONDecoder().decode(NumberScenesCommand.Report.self, from: data)
    #expect(report.dryRun)
    #expect(report.gitignore == "would-add")
    #expect(report.files.count == 3)
    #expect(report.files[0].file == "episodes/01-one.fountain")
    #expect(report.files[0].count == 2)
    #expect(report.files[0].headings.map(\.number) == ["1", "2"])
  }

  @Test("`.personaje/` goes into .gitignore exactly once, and the episodes are byte-identical after a second run")
  func addsPersonajeToGitignoreOnce() throws {
    let project = try Synthetic.makeProject()
    // An existing .gitignore without a trailing newline keeps its lines.
    try Synthetic.write("build/", to: project.appendingPathComponent(".gitignore"))

    _ = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate)
    let afterFirst = try episodeData(project)
    let ignoreAfterFirst = try #require(gitignore(project))
    #expect(ignoreAfterFirst == "build/\n.personaje/\n")

    _ = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate.addingTimeInterval(60))
    let afterSecond = try episodeData(project)

    #expect(afterSecond == afterFirst)
    let ignore = try #require(gitignore(project))
    let occurrences = ignore.components(separatedBy: ".personaje/").count - 1
    #expect(occurrences == 1)
  }

  @Test("An existing .personaje/ entry is left alone, and nothing to number leaves .gitignore alone")
  func gitignoreUntouchedWhenCovered() throws {
    let project = try Synthetic.makeProject()
    let ignore = project.appendingPathComponent(".gitignore")
    try Synthetic.write("/.personaje\n", to: ignore)
    let result = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate)
    #expect(!result.output.contains(".gitignore"))
    #expect(try Synthetic.read(ignore) == "/.personaje\n")

    let clean = try Synthetic.makeProject()
    _ = try command(["--project", clean.path])
      .execute(workingDirectory: clean, now: Self.fixedDate)
    try FileManager.default.removeItem(at: clean.appendingPathComponent(".gitignore"))
    let again = try command(["--project", clean.path])
      .execute(workingDirectory: clean, now: Self.fixedDate.addingTimeInterval(60))
    #expect(again.failureCount == 0)
    #expect(gitignore(clean) == nil)
  }

  @Test("A file that fails is reported, the others are still numbered, and the failure count is non-zero")
  func failureContinuesAndCounts() throws {
    let project = try Synthetic.makeProject()
    let urls = Synthetic.episodeURLs(in: project, Self.names)
    // Something already at the backup path makes that file's backup fail.
    let blocked = project.appendingPathComponent(
      ".personaje/backups/20261118T120000Z/episodes/\(Self.names[0])")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    let firstBefore = try Data(contentsOf: urls[0])

    let result = try command(["--project", project.path])
      .execute(workingDirectory: project, now: Self.fixedDate)

    #expect(result.failureCount == 1)
    #expect(result.output.contains("episodes/\(Self.names[0]): FAILED"))
    #expect(try Data(contentsOf: urls[0]) == firstBefore)
    #expect(try Synthetic.read(urls[1]).contains("#1#"))
  }

  @Test("The timestamp is UTC ISO 8601 basic form, with no colons")
  func timestampFormat() {
    #expect(NumberScenesCommand.timestamp(Self.fixedDate) == "20261118T120000Z")
  }
}
