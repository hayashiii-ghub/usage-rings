import Foundation
import UsageCore

// Claude Code owns stdin. Never save the original payload or log its contents.
do {
    var data = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= 1_048_576 else { exit(0) }
    }
    if let input = try ClaudeStatusline.parse(data) {
        try ClaudeStatuslineFile.write(input)
        print(input.usage.windows.map { "\($0.title): \(Int($0.remainingPercent.rounded()))% left" }.joined(separator: " · "))
    } else {
        print("Claude")
    }
} catch {
    // Status-line failures must not interrupt Claude Code or expose session data.
    print("Claude")
}
