import Foundation

@main struct ProfileSyncV1HostMain {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass this checkout's repository root") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        print("Swift real v2 + profile-sync codecs: " + (try ProfileSyncV1FixtureConformance.run(root: root)))
        print("No auth, native apply, core/OS registry adapter, UI, storage or physical qualification")
    }
}
