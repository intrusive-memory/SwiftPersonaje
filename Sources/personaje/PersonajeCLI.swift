import ArgumentParser
import PersonajeCLICore

@main
struct PersonajeCLI: AsyncParsableCommand {
  static let configuration = PersonajeCommand.configuration
}
