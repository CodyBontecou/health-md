import Foundation

private actor Calls {
    var count = 0
    func increment() { count += 1 }
}
private func hex(_ s: String) -> Data { Data(stride(from:0,to:s.count,by:2).map { i in let start=s.index(s.startIndex,offsetBy:i); return UInt8(s[start..<s.index(start,offsetBy:2)],radix:16)! }) }
private nonisolated func evidence(_ request: ReceiverCoverageRequest, days: [String]) throws -> ReceiverCoverageOutcome {
    var value = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
    value["schema"] = "healthmd.receiver_coverage.response"; value["completed_dates"] = days
    return .valid(try ReceiverCoverageEvidence.parse(JSONSerialization.data(withJSONObject:value), for:request))
}
@main struct PlanTests {
    static func main() async throws {
        let preflight = /*PREPARE*/!
        for line in try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8).split(separator:"\n") {
            let p = line.split(separator:"\t")
            let text = String(decoding:Data(base64Encoded:String(p[2]))!,as:UTF8.self)
            do { let plan = try ReceiverCoveragePlan.restore(text,binding:String(repeating:"a",count:64)); precondition(p[1] == "valid"); print("\(p[0])\t\(try plan.json().data(using:.utf8)!.base64EncodedString())") }
            catch { precondition(p[1] == "invalid", "Rejected valid plan \(p[0]): \(error)"); print("\(p[0])\tinvalid") }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let journal = ReceiverCoverageJournal(directory:directory)
        let calls = Calls()
        let now = Date(timeIntervalSince1970:1773043200)
        let candidates = ["2026-03-06","2026-03-07","2026-03-08"]
        let plan = try await journal.resolve(id:"occurrence",authority:"profile:g1:fire1",preflight:preflight,candidates:candidates,now:now,todayRefresh:true,authorized:{true},query:{ request in
            await calls.increment(); return try evidence(request,days:["2026-03-06","2026-03-08"])
        })
        precondition(plan.selected == ["2026-03-07","2026-03-08","2026-03-09"])
        try journal.acknowledge(id:"occurrence",authority:"profile:g1:fire1",binding:preflight.destinationBinding,dates:["2026-03-07","2026-03-09"])
        let restarted = ReceiverCoverageJournal(directory:directory)
        let retry = try await restarted.resolve(id:"occurrence",authority:"profile:g1:fire1",preflight:preflight,candidates:["2050-01-01"],now:now.addingTimeInterval(864000),todayRefresh:false,authorized:{true},query:{ _ in fatalError("Retry queried receiver") })
        precondition(retry.residual == ["2026-03-08"] && retry.today == "2026-03-09")
        let path = directory.appendingPathComponent("occurrence.json")
        let saved = try Data(contentsOf:path)
        do { _ = try restarted.restore(id:"occurrence",authority:"changed",binding:preflight.destinationBinding); fatalError("Changed authority restored") } catch {}
        do { _ = try restarted.restore(id:"occurrence",authority:"profile:g1:fire1",binding:String(repeating:"b",count:64)); fatalError("Changed binding restored") } catch {}
        do { try restarted.acknowledge(id:"occurrence",authority:"profile:g1:fire1",binding:preflight.destinationBinding,dates:["2026-03-06"]); fatalError("Unselected acknowledgement accepted") } catch {}
        let after = try Data(contentsOf:path); precondition(saved == after)
        do { _ = try await journal.resolve(id:"cancelled",authority:"g1",preflight:preflight,candidates:candidates,now:now,todayRefresh:false,authorized:{true},query:{ _ in await calls.increment(); throw CancellationError() }); fatalError("Cancellation swallowed") } catch is CancellationError {}
        let recovered = try await restarted.resolve(id:"cancelled",authority:"g1",preflight:preflight,candidates:[],now:now,todayRefresh:false,authorized:{true},query:{_ in fatalError("Crashed preflight repeated")})
        precondition(recovered.residual == candidates && recovered.status == "fallback_full")
        let emptyPreflight = try ReceiverCoveragePreflight.prepare(policy:.missingDays,uploadURL:preflight.uploadURL.absoluteString,preflightURL:preflight.preflightURL.absoluteString,uploadHeaders:["Authorization":"Bearer synthetic","X-Tenant":"synthetic"],scopeID:preflight.scopeID,calendarTimeZone:preflight.calendarTimeZoneIdentifier,frozenOutputSettings:Data("{\"profile\":\"synthetic\"}".utf8),refreshRecentDays:0,installationKey:Data(repeating:1,count:32))!
        let empty = try await journal.resolve(id:"empty",authority:"g1",preflight:emptyPreflight,candidates:candidates,now:now,todayRefresh:false,authorized:{true},query:{try evidence($0,days:candidates)})
        precondition(empty.selected.isEmpty && empty.residual.isEmpty)
        let emptyRetry = try await restarted.resolve(id:"empty",authority:"g1",preflight:emptyPreflight,candidates:[],now:now,todayRefresh:true,authorized:{true},query:{_ in fatalError("Empty plan reselected")})
        precondition(emptyRetry.residual.isEmpty)
        let bad = directory.appendingPathComponent("file")
        try Data([1]).write(to:bad)
        do { _ = try await ReceiverCoverageJournal(directory:bad).resolve(id:"blocked",authority:"g1",preflight:preflight,candidates:candidates,now:now,todayRefresh:false,authorized:{true},query:{_ in fatalError("HTTP before durable admission")}); fatalError("Write failure ignored") } catch {}
        let count = await calls.count; precondition(count == 2)
        print("transport\tok")
    }
}
