// SDK data seams only. The actual secure-key policy, settings and scope-binding code is compiled.
import Foundation
protocol KeychainStoring: Sendable {
    func readStringOrThrow(key:String) throws -> String?
    func writeStringOrThrow(key:String,value:String) throws
}
struct SystemKeychainStore:KeychainStoring {
    func readStringOrThrow(key:String)throws->String? {fatalError("System keychain touched in host test")}
    func writeStringOrThrow(key:String,value:String)throws {fatalError("System keychain touched in host test")}
}
struct ExportSettingsSnapshot:Codable {
    static let durableSleepContextEncoding=CodingUserInfoKey(rawValue:"durable")!
    var exportFormats:Set<String>
}
