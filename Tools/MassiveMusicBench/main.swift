import Foundation
import MassiveMusicCore

let directory = FileManager.default.temporaryDirectory
    .appending(path: "MassiveMusicBench-\(UUID().uuidString)", directoryHint: .isDirectory)
let databaseURL = directory.appending(path: "benchmark.sqlite")
do {
    let database = try LibraryDatabase(url: databaseURL)
    let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 360_000
    let result = try database.benchmarkSynthetic(count: count)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("Benchmark failed: \(error)\n".utf8))
    exit(1)
}

