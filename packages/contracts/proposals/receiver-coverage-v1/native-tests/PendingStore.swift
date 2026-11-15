import Foundation
@main struct PendingStoreHarness {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let defaults=UserDefaults(suiteName:UUID().uuidString)!
        let path=root.appendingPathComponent("pending.json")
        let config=ReceiverCoverageConfiguration(preflightURL:"https://example.com/coverage",scopeID:"scope-1",refreshRecentDays:1)
        let dates=[Date(timeIntervalSince1970:1772841600),Date(timeIntervalSince1970:1772928000)]
        let request=PendingExportRequest(dates:dates,source:.scheduled,scheduledFireDate:Date(),exportTarget:.apiEndpoint,receiverCoverage:config)
        let store=PendingExportStore(userDefaults:defaults,receiverJournalURL:path)
        try store.upsert(request)
        precondition(defaults.data(forKey:PendingExportStore.storageKey)==nil)
        let restarted=PendingExportStore(userDefaults:defaults,receiverJournalURL:path)
        let saved=try restarted.loadAll(); precondition(saved == [request])
        let unchanged = try Data(contentsOf:path)
        let changed = PendingExportRequest(id:request.id,dates:dates,source:.scheduled,scheduledFireDate:request.scheduledFireDate,exportTarget:.apiEndpoint,
            receiverCoverage:ReceiverCoverageConfiguration(preflightURL:"https://example.com/other",scopeID:"other-scope",refreshRecentDays:0))
        do { try restarted.upsert(changed); fatalError("Existing receiver authority changed") } catch {}
        let preserved = try Data(contentsOf:path); precondition(preserved == unchanged)
        let partial=request.replacingResidualDates([request.dates[1]],attemptedAt:Date())
        try restarted.upsert(partial)
        let reloaded=try store.loadAll(); precondition(reloaded[0].dates==partial.dates && reloaded[0].originalRequestedDates==request.originalRequestedDates && reloaded[0].receiverCoverage==config)
        let empty=partial.replacingResidualDates([],attemptedAt:Date())
        try store.upsert(empty)
        let emptySaved=try restarted.loadAll(); precondition(emptySaved[0].dates.isEmpty)
        try store.clearCompletedRequests(ids:[request.id]); let cleared=try restarted.loadAll(); precondition(cleared.isEmpty)
        try store.upsert(request)
        var unknown = try JSONSerialization.jsonObject(with:Data(contentsOf:path)) as! [String:Any]
        unknown["version"] = 2
        let future = try JSONSerialization.data(withJSONObject:unknown)
        try future.write(to:path)
        do {_ = try restarted.loadAll(); fatalError("Unknown receiver queue became empty") } catch {}
        do {try restarted.upsert(request); fatalError("Unknown receiver queue overwritten") } catch {}
        let futureSaved = try Data(contentsOf:path); precondition(futureSaved == future)
        try Data("not-json".utf8).write(to:path)
        do {_ = try restarted.loadAll(); fatalError("Corrupt receiver queue became empty") } catch {}
        do {try restarted.upsert(request); fatalError("Corrupt receiver queue overwritten") } catch {}
        let corrupt=try String(contentsOf:path,encoding:.utf8); precondition(corrupt=="not-json")
        print("Actual PendingExportStore: restart, partial residuals, empty completion, corruption preservation passed")
    }
}
