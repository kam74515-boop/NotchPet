//
//  AgentHTTPListener.swift
//  NotchPet — AI coding-agent task sync
//
//  Loopback-only HTTP server (Network.framework, no third-party deps) that receives
//  agent lifecycle events from the bundled hook script. Protocol-compatible with
//  clawd-on-desk: ports 23333–23337 round-robin, GET/POST /state, POST /permission,
//  and an `x-clawd-server` response header.
//

import Foundation
import Network

enum PermissionDecision: String { case allow, deny, wait }

struct PermissionRequestPayload {
    let toolName: String
    let sessionId: String
    let rawJSON: [String: Any]
}

/// Minimal HTTP/1.1 request, parsed from a raw byte buffer.
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    /// Returns a parsed request only once the full body (per Content-Length) has arrived.
    init?(raw: Data) {
        guard let headerEndRange = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = raw.subdata(in: raw.startIndex..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])

        let target = String(parts[1])
        if let qIdx = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<qIdx])
            var q: [String: String] = [:]
            let qs = target[target.index(after: qIdx)...]
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    q[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                } else if kv.count == 1 {
                    q[String(kv[0])] = ""
                }
            }
            query = q
        } else {
            path = target
            query = [:]
        }

        var h: [String: String] = [:]
        for line in lines.dropFirst() where line.contains(":") {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2 {
                h[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                    kv[1].trimmingCharacters(in: .whitespaces)
            }
        }
        headers = h

        let bodyStart = headerEndRange.upperBound
        let available = raw.subdata(in: bodyStart..<raw.endIndex)
        let contentLength = Int(h["content-length"] ?? "0") ?? 0
        if available.count < contentLength { return nil } // wait for more
        body = contentLength > 0 ? available.subdata(in: available.startIndex..<available.index(available.startIndex, offsetBy: contentLength)) : Data()
    }
}

final class AgentHTTPListener {
    static let serverIdentity = "notchpet"

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "notchpet.agentsync.listener")
    // Own port range, distinct from Clawd on Desk (23333–23337), so both can coexist.
    private let candidatePorts: [UInt16] = [24333, 24334, 24335, 24336, 24337]
    private var portIndex = 0
    private let maxBodyBytes = 512 * 1024

    private(set) var activePort: UInt16?
    var onPortBound: ((UInt16) -> Void)?
    var onPermission: ((PermissionRequestPayload, @escaping (PermissionDecision) -> Void) -> Void)?

    func start() {
        queue.async { [weak self] in
            self?.portIndex = 0
            self?.bindNext()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.activePort = nil
        }
    }

    private func bindNext() {
        guard portIndex < candidatePorts.count else {
            NSLog("NotchPet AgentSync: no free port in 23333–23337; sync disabled")
            return
        }
        let port = candidatePorts[portIndex]
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: nwPort) else {
            portIndex += 1
            bindNext()
            return
        }

        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.activePort = port
                self.onPortBound?(port)
            case .failed, .cancelled:
                if self.activePort == nil { // binding failed → try next port
                    l.cancel()
                    self.portIndex += 1
                    self.bindNext()
                }
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)
        listener = l
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if buf.count > self.maxBodyBytes {
                self.respond(conn, status: "413 Payload Too Large", json: ["error": "too large"])
                return
            }
            if let req = HTTPRequest(raw: buf) {
                self.route(req, conn)
            } else if isComplete || error != nil {
                self.respond(conn, status: "400 Bad Request", json: ["error": "bad request"])
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func route(_ req: HTTPRequest, _ conn: NWConnection) {
        switch (req.method, req.path) {
        case ("GET", "/state"), ("GET", "/health"):
            respond(conn, status: "200 OK", json: ["app": Self.serverIdentity, "port": Int(activePort ?? 0)])

        case ("POST", "/state"):
            let eventName = req.query["event"] ?? (jsonObject(req.body)?["event"] as? String) ?? ""
            let agentId = req.query["agent"]
            if let event = try? JSONDecoder().decode(AgentEvent.self, from: req.body) {
                Task { @MainActor in
                    AgentSessionStore.shared.ingest(event: eventName.isEmpty ? (event.event ?? "") : eventName,
                                                    payload: event, agentIdOverride: agentId)
                }
            }
            respond(conn, status: "200 OK", json: [:])

        case ("POST", "/permission"):
            handlePermission(req, conn)

        default:
            respond(conn, status: "404 Not Found", json: ["error": "not found"])
        }
    }

    private func handlePermission(_ req: HTTPRequest, _ conn: NWConnection) {
        guard let onPermission else {
            // Permission bubbles disabled → empty 200 means "no decision", so Claude Code
            // falls back to its own (terminal) permission flow.
            respond(conn, status: "200 OK", json: [:])
            return
        }
        let obj = jsonObject(req.body) ?? [:]
        let payload = PermissionRequestPayload(
            toolName: obj["tool_name"] as? String ?? "tool",
            sessionId: obj["session_id"] as? String ?? "default",
            rawJSON: obj
        )
        Task { @MainActor in
            onPermission(payload) { [weak self] decision in
                self?.queue.async {
                    // Official Claude Code PermissionRequest hook response shape.
                    let mapped = decision == .allow ? "allow" : (decision == .deny ? "deny" : "ask")
                    self?.respond(conn, status: "200 OK", json: [
                        "hookSpecificOutput": [
                            "hookEventName": "PermissionRequest",
                            "permissionDecision": mapped,
                        ],
                    ])
                }
            }
        }
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func respond(_ conn: NWConnection, status: String, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "x-clawd-server: \(Self.serverIdentity)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
