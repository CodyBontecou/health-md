//
//  PricingAnalyticsClient.swift
//  HealthMd
//
//  Offline-safe client for pricing analytics.
//

import Foundation

nonisolated final class PricingAnalyticsClient: @unchecked Sendable {
    static let shared = PricingAnalyticsClient(
        transport: NoOpPricingAnalyticsTransport()
    )

    private static let defaultQueueKey = "pricing.analytics.queue.v1"
    private static let defaultQueueSize = 50
    private static let defaultRetryDelayNanoseconds: UInt64 = 30_000_000_000

    private let isEnabled: Bool
    private let state: PricingAnalyticsClientState
    private let transport: PricingAnalyticsTransport

    init(
        transport: PricingAnalyticsTransport,
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        queueKey: String = PricingAnalyticsClient.defaultQueueKey,
        maxQueueSize: Int = PricingAnalyticsClient.defaultQueueSize,
        isEnabled: Bool = PricingAnalyticsClient.isEnabledByDefault,
        retryDelayNanoseconds: UInt64 = PricingAnalyticsClient.defaultRetryDelayNanoseconds
    ) {
        self.isEnabled = isEnabled
        self.transport = transport
        self.state = PricingAnalyticsClientState(
            store: PricingAnalyticsQueueStore(defaults: defaults, key: queueKey),
            maxQueueSize: max(0, maxQueueSize),
            retryDelayNanoseconds: retryDelayNanoseconds
        )
    }

    func track(_ event: PricingAnalyticsEvent) {
        guard isEnabled else { return }

        state.enqueue(event.encodedPayload())
        state.startFlushIfNeeded(transport: transport)
    }

    func flush() {
        guard isEnabled else { return }

        state.startFlushIfNeeded(transport: transport)
    }

    func flushAndWait() async {
        guard isEnabled else { return }

        await state.flushAndWait(transport: transport)
    }

    func queuedPayloads() async -> [PricingAnalyticsPayload] {
        state.queuedPayloads()
    }

    private static var isEnabledByDefault: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PRICING_ANALYTICS_ENABLED"] == "1"
        #else
        true
        #endif
    }
}

nonisolated private final class PricingAnalyticsClientState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.codybontecou.healthmd.pricing-analytics-client")
    private let store: PricingAnalyticsQueueStore
    private let maxQueueSize: Int
    private let retryDelayNanoseconds: UInt64

    private var payloads: [PricingAnalyticsPayload]
    private var flushTask: Task<Void, Never>?

    init(store: PricingAnalyticsQueueStore, maxQueueSize: Int, retryDelayNanoseconds: UInt64) {
        self.store = store
        self.maxQueueSize = maxQueueSize
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.payloads = store.load()
        trimToQueueCap()
        store.save(payloads)
    }

    func enqueue(_ payload: PricingAnalyticsPayload) {
        queue.sync {
            payloads.append(payload)
            trimToQueueCap()
            store.save(payloads)
        }
    }

    func startFlushIfNeeded(transport: PricingAnalyticsTransport) {
        queue.sync {
            guard flushTask == nil else { return }

            flushTask = Task.detached(priority: .background) { [weak self, transport] in
                await self?.flushLoop(transport: transport)
            }
        }
    }

    func flushAndWait(transport: PricingAnalyticsTransport) async {
        startFlushIfNeeded(transport: transport)

        let task = queue.sync { flushTask }
        await task?.value
    }

    func queuedPayloads() -> [PricingAnalyticsPayload] {
        queue.sync { payloads }
    }

    private func flushLoop(transport: PricingAnalyticsTransport) async {
        var stoppedAfterFailure = false

        while let payload = nextPayload() {
            do {
                try await transport.send(payload)
                removeSentPayload(payload)
            } catch {
                stoppedAfterFailure = true
                break
            }
        }

        queue.sync {
            if payloads.isEmpty {
                flushTask = nil
            } else if stoppedAfterFailure {
                flushTask = Task.detached(priority: .background) { [weak self, transport, retryDelayNanoseconds] in
                    if retryDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    }
                    await self?.flushLoop(transport: transport)
                }
            } else {
                flushTask = Task.detached(priority: .background) { [weak self, transport] in
                    await self?.flushLoop(transport: transport)
                }
            }
        }
    }

    private func nextPayload() -> PricingAnalyticsPayload? {
        queue.sync { payloads.first }
    }

    private func removeSentPayload(_ payload: PricingAnalyticsPayload) {
        queue.sync {
            guard payloads.first == payload else { return }

            payloads.removeFirst()
            store.save(payloads)
        }
    }

    private func trimToQueueCap() {
        guard maxQueueSize > 0 else {
            payloads.removeAll()
            return
        }

        if payloads.count > maxQueueSize {
            payloads.removeFirst(payloads.count - maxQueueSize)
        }
    }
}

nonisolated private struct PricingAnalyticsQueueStore: Sendable {
    private let defaults: UserDefaultsStoring
    private let key: String

    init(defaults: UserDefaultsStoring, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [PricingAnalyticsPayload] {
        guard let data = defaults.data(forKey: key) else { return [] }

        let decoder = JSONDecoder()
        return (try? decoder.decode([PricingAnalyticsPayload].self, from: data)) ?? []
    }

    func save(_ payloads: [PricingAnalyticsPayload]) {
        guard !payloads.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(payloads) {
            defaults.set(data, forKey: key)
        }
    }
}
