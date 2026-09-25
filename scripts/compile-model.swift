import CoreML
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: compile-model.swift input.mlpackage output.mlmodelc\n", stderr)
    exit(1)
}
do {
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let destination = URL(fileURLWithPath: CommandLine.arguments[2])
    let compiled = try MLModel.compileModel(at: source)
    defer { try? FileManager.default.removeItem(at: compiled) }
    try FileManager.default.copyItem(at: compiled, to: destination)
} catch {
    fputs("Model compilation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
