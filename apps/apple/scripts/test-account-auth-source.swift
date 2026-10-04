import Foundation

@main
struct AccountAuthSourceHarness {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            print("FAIL harness-arguments")
            exit(2)
        }
        do {
            let root = URL(fileURLWithPath: CommandLine.arguments[1])
            print("PASS \(try AccountAuthWireChecks.run(root: root))")
            print("PASS \(try AccountAuthCallbackChecks.run(root: root))")
            print("PASS \(try AccountAuthTransportChecks.run(root: root))")
            print("PASS \(try await AccountAuthLifecycleChecks.run(root: root))")
            print("PASS \(try await AccountAuthTemporalChecks.run(root: root))")
        } catch let error as AccountAuthTestCheck.Failed {
            // Categories contain only handwritten names or corpus indices, never private input.
            print("FAIL \(error.category)")
            exit(1)
        } catch {
            // Never print errors, raw bodies, identifiers or credential-bearing objects.
            print("FAIL source-check")
            exit(1)
        }
    }
}
