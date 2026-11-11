import Foundation
private nonisolated final class MemoryKeychain:KeychainStoring,@unchecked Sendable {
    let lock=NSLock()
    var values:[String:String]=[:]
    func readStringOrThrow(key:String)throws->String? {lock.lock(); defer{lock.unlock()}; return values[key]}
    func writeStringOrThrow(key:String,value:String)throws {lock.lock(); defer{lock.unlock()}; values[key]=value}
}
@main struct RuntimeTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let keys=MemoryKeychain()
        let runtime=ReceiverCoverageSettings(keychain:keys,storageDirectory:root)
        do{_ = try runtime.key(); fatalError("Missing recovery key replaced")}catch{}
        let key=try runtime.key(create:true); precondition(key.count==32)
        let restarted=ReceiverCoverageSettings(keychain:keys,storageDirectory:root)
        let restored=try restarted.key(); precondition(restored==key)
        let config=ReceiverCoverageConfiguration(preflightURL:"https://example.com/coverage",scopeID:"scope-1",refreshRecentDays:0)
        try runtime.save(config,scope:"profile-1",uploadURL:"https://example.com/upload")
        let saved=try restarted.configuration("profile-1"); precondition(saved==config)
        try runtime.bindScope("scope-1",settings:Data("original-output".utf8))
        try restarted.bindScope("scope-1",settings:Data("original-output".utf8))
        do{try restarted.bindScope("scope-1",settings:Data("edited-output".utf8)); fatalError("Scope reused after output edit")}catch{}
        do{try runtime.bindScope("../escape",settings:Data()); fatalError("Scope escaped directory")}catch{}
        let first=try ReceiverCoverageSettings.snapshotBytes(ExportSettingsSnapshot(exportFormats:Set(["json","markdown"])))
        let second=try ReceiverCoverageSettings.snapshotBytes(ExportSettingsSnapshot(exportFormats:Set(["markdown","json"])))
        precondition(first==second)
        try runtime.save(nil,scope:"profile-1",uploadURL:"")
        let disabled=try restarted.configuration("profile-1"); precondition(disabled==nil)
        let plans=root.appendingPathComponent("plans")
        try FileManager.default.createDirectory(at:plans,withIntermediateDirectories:true)
        try Data("saved-plan".utf8).write(to:plans.appendingPathComponent("pending.json"))
        let lost=ReceiverCoverageSettings(keychain:MemoryKeychain(),storageDirectory:root)
        do{_ = try lost.key(create:true); fatalError("Lost recovery key rotated")}catch{}
        let count=keys.values.count; precondition(count==1)
        print("Runtime secure-key ownership, scope binding, configuration persistence and stable settings passed")
    }
}
