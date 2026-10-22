import Foundation
import Testing

@testable import SwiftPersonaje

@Suite("Project resolution (SP-8) and screenplay listing (§7)")
struct PersonajeProjectTests {

  @Test("The nearest PROJECT.md at or above the working directory wins")
  func locatesNearestProject() throws {
    let project = try Synthetic.makeProject()
    let deep = project.appendingPathComponent("episodes/a/b", isDirectory: true)
    try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

    #expect(try PersonajeProject.locate(project: nil, workingDirectory: deep).directory == project)
    #expect(
      try PersonajeProject.locate(project: nil, workingDirectory: project).directory == project)
  }

  @Test("--project accepts the directory or its PROJECT.md")
  func explicitProject() throws {
    let project = try Synthetic.makeProject()
    let elsewhere = try Synthetic.makeDirectory()
    #expect(
      try PersonajeProject.locate(project: project.path, workingDirectory: elsewhere).directory
        == project)
    #expect(
      try PersonajeProject.locate(
        project: project.appendingPathComponent("PROJECT.md").path, workingDirectory: elsewhere
      ).directory == project)
  }

  @Test("No PROJECT.md is an error")
  func missingProject() throws {
    let empty = try Synthetic.makeDirectory()
    #expect(throws: PersonajeProjectError.projectFileMissing(empty.path)) {
      try PersonajeProject.locate(project: empty.path, workingDirectory: empty)
    }
  }

  @Test("CAST.md sits beside PROJECT.md")
  func castFileLocation() throws {
    let project = try Synthetic.makeProject()
    let opened = try PersonajeProject(directory: project)
    #expect(opened.castFile == project.appendingPathComponent("CAST.md"))
  }

  @Test("Defaults: episodes/ and *.fountain, sorted")
  func defaults() throws {
    let project = try Synthetic.makeProject()
    let opened = try PersonajeProject(directory: project)
    #expect(opened.screenplayPatterns == ["*.fountain"])
    #expect(
      opened.screenplayFiles().map(\.lastPathComponent)
        == ["01-one.fountain", "02-two.fountain", "03-three.fountain"])
  }

  @Test("A comma-separated filePattern names the episode files one by one")
  func commaSeparatedFilePattern() throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: "filePattern: \"01-one.fountain, 03-three.fountain\"")
    let opened = try PersonajeProject(directory: project)
    #expect(opened.screenplayPatterns == ["01-one.fountain", "03-three.fountain"])
    #expect(
      opened.screenplayFiles().map(\.lastPathComponent)
        == ["01-one.fountain", "03-three.fountain"])
  }

  @Test("episodesDir and a list filePattern are honoured, recursively")
  func episodesDirAndListPattern() throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: """
        episodesDir: scripts
        filePattern:
          - "*.fountain"
          - "*.fdx"
        """)
    let scripts = project.appendingPathComponent("scripts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: scripts.appendingPathComponent("s1"), withIntermediateDirectories: true)
    try Synthetic.write(Synthetic.episodeOne, to: scripts.appendingPathComponent("s1/a.fountain"))
    try Synthetic.write("notes", to: scripts.appendingPathComponent("readme.txt"))

    let opened = try PersonajeProject(directory: project)
    #expect(opened.screenplayFiles().map(\.lastPathComponent) == ["a.fountain"])
  }

  @Test("A legacy cast: block is detected")
  func legacyCastBlock() throws {
    let project = try Synthetic.makeProject(
      frontMatterExtra: """
        cast:
          - character: BOB
        """)
    #expect(try PersonajeProject(directory: project).hasLegacyCastBlock)
    #expect(try !PersonajeProject(directory: Synthetic.makeProject()).hasLegacyCastBlock)
  }
}
