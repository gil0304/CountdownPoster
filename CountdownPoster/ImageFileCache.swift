import Foundation

enum ImageFileCache {
    static func save(data: Data, prefix: String, fileExtension: String) throws -> URL {
        let directory = try cacheDirectory()
        let filename = "\(prefix)-\(UUID().uuidString).\(fileExtension)"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("CountdownPosterImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
