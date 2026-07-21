import Darwin
import Foundation
import HealthMdMCPCore

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
            configuration = try HealthMdMCPConfiguration(
                baseURL: baseURL,
                bearerToken: environment["HEALTHMD_AGENT_TOKEN"]
            )
        } catch {
            fputs("healthmd-mcp requires an HTTP loopback Health.md endpoint\n", stderr)
            Foundation.exit(2)
        }

        let server = HealthMdMCPServer(configuration: configuration)
        let maximumRequestBytes = 2 * 1_024 * 1_024
        while let line = readLine(strippingNewline: true) {
            guard line.utf8.count <= maximumRequestBytes else {
                print(#"{"error":{"code":-32600,"message":"Request too large"},"id":null,"jsonrpc":"2.0"}"#)
                continue
            }
            if let response = await server.handle(line: line) {
                print(response)
            }
        }
    }
}
