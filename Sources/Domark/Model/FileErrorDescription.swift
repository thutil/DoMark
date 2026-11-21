import Foundation

/// A human explanation of why a file couldn't be read or written.
/// Foundation's own text is often just "The operation couldn’t be completed. (NSCocoaErrorDomain error 256.)",
/// which says nothing — so check the usual causes first and fall back to the underlying POSIX reason.
enum FileErrorDescription {
    static func reading(_ url: URL, error: Error) -> String {
        let name = url.lastPathComponent
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return "“\(name)” no longer exists — it may have been moved, renamed or deleted."
        }
        if isDirectory.boolValue {
            return "“\(name)” is a folder, not a file."
        }
        if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
           status != .current {
            return "“\(name)” is in iCloud and hasn’t been downloaded to this Mac yet. Open it in Finder to download it, then press ⌘R."
        }
        if !fm.isReadableFile(atPath: url.path) {
            return "Domark doesn’t have permission to read “\(name)”. Check the file’s permissions, or allow Domark under System Settings › Privacy & Security › Files and Folders."
        }
        return describe(error)
    }

    /// The error's own text, plus the low-level reason when Foundation hides it behind a generic message
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = nsError.localizedDescription
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let reason = underlying.localizedFailureReason
                ?? (underlying.domain == NSPOSIXErrorDomain ? String(cString: strerror(Int32(underlying.code))) : underlying.localizedDescription)
            if !text.contains(reason) { text += " (\(reason))" }
        }
        return unescape(text)
    }

    /// Some system error strings arrive with old-style plist escapes left in ("couldn\U2019t") — turn them back into characters
    static func unescape(_ text: String) -> String {
        guard text.contains("\\U") else { return text }
        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: "\\U") {
            result += rest[..<range.lowerBound]
            let hex = rest[range.upperBound...].prefix(4)
            if hex.count == 4, let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
                rest = rest[rest.index(range.upperBound, offsetBy: 4)...]
            } else {
                result += "\\U"
                rest = rest[range.upperBound...]
            }
        }
        return result + rest
    }
}
