/// One-way authority barrier around destination commit. Actor isolation prevents two concurrent
/// owners from racing a commit transition without blocking the main actor.
actor ExportCommitBarrier {
    enum State: String, Codable, CaseIterable, Equatable, Sendable {
        case planned
        case materialized
        case committing
        case completed
        case failed
    }

    enum BarrierError: String, Error, Equatable, Sendable {
        case invalidTransition
        case authorityLocked
    }

    private(set) var state: State = .planned

    func transition(to next: State) throws {
        let allowed: Bool = switch (state, next) {
        case (.planned, .materialized),
             (.planned, .failed),
             (.materialized, .committing),
             (.materialized, .failed),
             (.committing, .completed),
             (.committing, .failed):
            true
        default:
            false
        }
        guard allowed else { throw BarrierError.invalidTransition }
        state = next
    }

    /// Authority may change only while no destination commit has started.
    func authorizeAuthorityFallback() throws {
        guard state == .planned || state == .materialized else {
            throw BarrierError.authorityLocked
        }
    }

    /// Rerendering is allowed before commit and forbidden from the first committing transition on.
    func authorizeRerender() throws {
        guard state == .planned || state == .materialized else {
            throw BarrierError.authorityLocked
        }
    }
}
