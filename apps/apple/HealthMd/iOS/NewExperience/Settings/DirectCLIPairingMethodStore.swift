import Foundation

/// How the saved CLI pairing was made, for CLIDestG's "Paired via QR" line.
///
/// The direct service saves only the trusted CLI and when it paired. This store notes
/// the method when a pairing attempt starts (a scanned QR link, or a typed code) and
/// binds it to the pairing date once a new pairing appears, so later reconnects and
/// unrelated attempts never relabel an existing pairing. Local only, no health data.
struct DirectCLIPairingMethodStore {
    enum Method: String, Codable, Equatable {
        case qr
        case code
    }

    private struct Record: Codable, Equatable {
        let method: Method
        let date: Date
    }

    static let pendingKey = "directCLI.pairingMethod.pending"
    static let recordedKey = "directCLI.pairingMethod.recorded"

    var defaults: UserDefaults = .standard

    /// Call when a pairing attempt starts.
    func noteAttempt(_ method: Method, at date: Date = Date()) {
        write(Record(method: method, date: date), forKey: Self.pendingKey)
    }

    /// The method for the pairing saved at `pairedAt`, recording it on first sight.
    /// Nil when the pairing predates this record (or no attempt was seen), so the
    /// screen never guesses.
    @discardableResult
    func method(forPairingAt pairedAt: Date?) -> Method? {
        guard let pairedAt else { return nil }
        if let recorded = read(Self.recordedKey), recorded.date == pairedAt {
            return recorded.method
        }
        // A pairing saved after the latest attempt started came from that attempt.
        guard let pending = read(Self.pendingKey), pairedAt >= pending.date else { return nil }
        write(Record(method: pending.method, date: pairedAt), forKey: Self.recordedKey)
        defaults.removeObject(forKey: Self.pendingKey)
        return pending.method
    }

    func forget() {
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.recordedKey)
    }

    private func read(_ key: String) -> Record? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    private func write(_ record: Record, forKey key: String) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: key) }
    }
}
