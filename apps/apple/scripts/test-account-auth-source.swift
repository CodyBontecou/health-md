import Foundation

@main
struct AccountAuthSourceHarness {
    static func main() async {
        guard (2...3).contains(CommandLine.arguments.count) else {
            print("FAIL harness-arguments")
            exit(2)
        }
        do {
            let root = URL(fileURLWithPath: CommandLine.arguments[1])
            let headerRoot = CommandLine.arguments.count == 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : root
            print("PASS \(try AccountAuthWireChecks.run(root: root))")
            print("PASS \(try AccountAuthCallbackChecks.run(root: root))")
            print("PASS \(try AccountAuthTransportChecks.run(root: root))")
            print("PASS \(try AccountAuthReplyHeaderChecks.run(root: root, headerRoot: headerRoot))")
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
