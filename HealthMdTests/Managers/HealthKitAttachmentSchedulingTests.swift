import XCTest
@testable import HealthMd

final class HealthKitAttachmentSchedulingTests: XCTestCase {
    private actor ConcurrencyProbe {
        private var active = 0
        private var maximum = 0
        private var firstWaveWaiters: [CheckedContinuation<Void, Never>] = []

        func enter(index: Int, firstWaveSize: Int) async {
            active += 1
            maximum = max(maximum, active)
            guard index < firstWaveSize else { return }

            await withCheckedContinuation { continuation in
                firstWaveWaiters.append(continuation)
                guard firstWaveWaiters.count == firstWaveSize else { return }
                let ready = firstWaveWaiters
                firstWaveWaiters.removeAll()
                ready.forEach { $0.resume() }
            }
        }

        func leave() {
            active -= 1
        }

        var maximumObserved: Int { maximum }
    }

    func testBoundedOrderedMapRefillsDynamicallyAndRestoresInputOrder() async {
        let inputs = Array(0..<12)
        let limit = 4
        let probe = ConcurrencyProbe()

        let outputs = await HealthKitAttachmentWorkScheduler.boundedOrderedMap(
            inputs,
            limit: limit
        ) { index in
            await probe.enter(index: index, firstWaveSize: limit)
            try? await Task.sleep(for: .milliseconds((inputs.count - index) * 2))
            await probe.leave()
            return index * 10
        }

        let maximumObserved = await probe.maximumObserved
        XCTAssertEqual(outputs, inputs.map { $0 * 10 })
        XCTAssertEqual(maximumObserved, limit)
    }

    func testBoundedOrderedMapHandlesEmptyInputAndNormalizesInvalidLimit() async {
        let empty: [Int] = await HealthKitAttachmentWorkScheduler.boundedOrderedMap(
            [],
            limit: 0
        ) { $0 }
        XCTAssertTrue(empty.isEmpty)

        let probe = ConcurrencyProbe()
        let outputs = await HealthKitAttachmentWorkScheduler.boundedOrderedMap(
            Array(0..<4),
            limit: 0
        ) { index in
            await probe.enter(index: index, firstWaveSize: 1)
            await Task.yield()
            await probe.leave()
            return index
        }

        let maximumObserved = await probe.maximumObserved
        XCTAssertEqual(outputs, Array(0..<4))
        XCTAssertEqual(maximumObserved, 1)
    }

    func testAttachmentStagesUseIndependentConcurrencyLimits() {
        XCTAssertEqual(HealthKitAttachmentWorkScheduler.metadataConcurrencyLimit, 16)
        XCTAssertEqual(HealthKitAttachmentWorkScheduler.streamConcurrencyLimit, 4)
    }

    func testCancellationDoesNotStrandBoundedScheduler() async {
        let task = Task {
            await HealthKitAttachmentWorkScheduler.boundedOrderedMap(
                Array(0..<100),
                limit: 4
            ) { index in
                try? await Task.sleep(for: .seconds(5))
                return index
            }
        }

        await Task.yield()
        task.cancel()
        let outputs = await task.value
        XCTAssertEqual(outputs, Array(0..<100))
    }
}
