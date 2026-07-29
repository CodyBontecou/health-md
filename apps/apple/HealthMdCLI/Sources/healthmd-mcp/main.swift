import Darwin
import Foundation
#if SWIFT_PACKAGE
import HealthMdMCPCore
#endif

private actor MCPStandardOutputWriter {
    func write(_ line: String) {
        print(line)
    }
}

@main
struct HealthMdMCPExecutable {
    static func main() async {
        setbuf(stdout, nil)
        let environment = ProcessInfo.processInfo.environment
        let baseURL = environment["HEALTHMD_MCP_BASE_URL"]
            .flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:17645")!
        let configuration: HealthMdMCPConfiguration
        do {
            configuration = try HealthMdMCPConfiguration(baseURL: baseURL)
        } catch {
            fputs("healthmd-mcp requires an HTTP loopback Health.md endpoint\n", stderr)
            Foundation.exit(2)
        }

        let server = HealthMdMCPServer(configuration: configuration)
        let writer = MCPStandardOutputWriter()
        let maximumRequestBytes = 2 * 1_024 * 1_024
        await withTaskGroup(of: Void.self) { group in
            while let line = readLine(strippingNewline: true) {
                guard line.utf8.count <= maximumRequestBytes else {
                    await writer.write(
                        #"{"error":{"code":-32600,"message":"Request too large"},"id":null,"jsonrpc":"2.0"}"#
                    )
                    continue
                }
                let method = line.data(using: .utf8)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["method"] as? String
                if method == "initialize" || method == "notifications/initialized" {
                    if let response = await server.handle(line: line) {
                        await writer.write(response)
                    }
                    continue
                }
                group.addTask {
                    if let response = await server.handle(line: line) {
                        await writer.write(response)
                    }
                }
            }
            await group.waitForAll()
        }
    }
}
