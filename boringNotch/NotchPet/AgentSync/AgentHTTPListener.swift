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
    let requestId = UUID()
    let toolName: String
    let sessionId: String
    let rawJSON: [String: Any]

    var isHeadless: Bool { rawJSON["headless"] as? Bool == true }
}

/// Tracks whether a held permission/clarification request has already been answered in the notch,
/// so the connection-close watcher doesn't treat OUR own response as the client bailing out.
private final class HeldRequest {
    private let lock = NSLock()
    private var resolved = false
    func markResolved() { lock.lock(); resolved = true; lock.unlock() }
    var isResolved: Bool { lock.lock(); defer { lock.unlock() }; return resolved }
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
    // SERIAL: rapid hook events (UserPromptSubmit → PreToolUse → Stop …) must be applied in the
    // order they arrived, or a stale state can overwrite a newer one (e.g. the "working" update
    // never sticks). Held connections (clarification/permission) don't block the queue — they park
    // on stored closures + an async close watcher — so serial costs nothing here.
    private let queue = DispatchQueue(label: "notchpet.agentsync.listener")
    // Own port range, distinct from Clawd on Desk (23333–23337), so both can coexist.
    private let candidatePorts: [UInt16] = [24333, 24334, 24335, 24336, 24337]
    private var portIndex = 0
    private let maxBodyBytes = 512 * 1024

    private(set) var activePort: UInt16?
    var onPortBound: ((UInt16) -> Void)?
    var onPermission: ((PermissionRequestPayload, @escaping (PermissionDecision) -> Void) -> Void)?
    var onClarification: ((PendingClarification) -> Void)?

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

        case ("GET", "/sessions"):
            Task { @MainActor [weak self] in
                let list = AgentSessionStore.shared.orderedSessions.map { s -> [String: Any] in
                    ["id": s.id, "agent": s.agentId, "title": s.title, "state": s.state.rawValue,
                     "ctxPct": s.contextPercent ?? -1, "ctxUsed": s.contextUsed ?? -1, "ctxLimit": s.contextLimit ?? -1]
                }
                self?.respond(conn, status: "200 OK", json: ["sessions": list])
            }

        case ("POST", "/state"):
            let eventName = req.query["event"] ?? (jsonObject(req.body)?["event"] as? String) ?? ""
            let agentId = req.query["agent"]
            // Lenient decode never throws on a JSON object; fall back to an empty event so a
            // malformed body still registers the event (by name) instead of being dropped.
            let event = (try? JSONDecoder().decode(AgentEvent.self, from: req.body)) ?? AgentEvent()
            let name = eventName.isEmpty ? (event.event ?? "") : eventName
            if !name.isEmpty {
                Task { @MainActor in
                    AgentSessionStore.shared.ingest(event: name, payload: event, agentIdOverride: agentId)
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
        let obj = jsonObject(req.body) ?? [:]
        let toolName = obj["tool_name"] as? String ?? "tool"
        let sessionId = obj["session_id"] as? String ?? "default"

        // AskUserQuestion: answer it RIGHT IN the notch (clawd's mechanism). Hold the connection;
        // when the user picks, respond with decision.behavior="allow" + updatedInput.answers
        // (keyed by question text) so Claude Code completes the tool with that choice. "Go to
        // terminal" drops the socket (no-decision) so Claude Code shows its own questionnaire.
        if toolName == "AskUserQuestion", let toolInput = obj["tool_input"] as? [String: Any],
           let onClarification {
            let questions = Self.parseClarificationQuestions(toolInput)
            let held = HeldRequest()
            let clarId = UUID()
            let submit: ([String: String]) -> Void = { [weak self] answers in
                held.markResolved()
                self?.queue.async {
                    var updated = toolInput
                    updated["answers"] = answers
                    self?.respond(conn, status: "200 OK", json: [
                        "hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                               "decision": ["behavior": "allow", "updatedInput": updated]],
                    ])
                }
            }
            let goToTerminal: () -> Void = { [weak self] in
                held.markResolved()
                self?.queue.async { conn.cancel() }   // no-decision → Claude Code's own UI
            }
            let clar = PendingClarification(id: clarId, sessionId: sessionId, title: "",
                                            questions: questions,
                                            headless: obj["headless"] as? Bool == true,
                                            submit: submit, goToTerminal: goToTerminal)
            // If Claude Code answers the question elsewhere (e.g. in the terminal) it closes this
            // connection — clear the notch card so it doesn't linger as already-answered.
            monitorClose(conn, held: held) {
                Task { @MainActor in AgentSyncCoordinator.shared.dismissClarification(id: clarId) }
            }
            Task { @MainActor in
                AgentSessionStore.shared.markClarification(sessionId: sessionId, tool: toolName,
                                                           question: questions.first?.question)
                onClarification(clar)
            }
            return
        }

        guard let onPermission else {
            // Permission bubbles disabled → empty 200 means "no decision", so Claude Code
            // falls back to its own (terminal) permission flow.
            respond(conn, status: "200 OK", json: [:])
            return
        }
        let payload = PermissionRequestPayload(toolName: toolName, sessionId: sessionId, rawJSON: obj)
        let held = HeldRequest()
        // Same as clarification: if the request is resolved in the terminal, the client closes the
        // connection — clear the in-notch permission card instead of leaving it hanging.
        monitorClose(conn, held: held) {
            Task { @MainActor in AgentSyncCoordinator.shared.dismissPermission(requestId: payload.requestId) }
        }
        Task { @MainActor in
            onPermission(payload) { [weak self] decision in
                held.markResolved()
                self?.queue.async {
                    // Official Claude Code PermissionRequest response shape:
                    //   hookSpecificOutput.decision.behavior = "allow" | "deny".
                    // For .wait, return no decision so Claude Code falls back to its own prompt.
                    let json: [String: Any]
                    switch decision {
                    case .allow:
                        json = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                       "decision": ["behavior": "allow"]]]
                    case .deny:
                        json = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                       "decision": ["behavior": "deny"]]]
                    case .wait:
                        json = [:]
                    }
                    self?.respond(conn, status: "200 OK", json: json)
                }
            }
        }
    }

    /// Watch a held connection: if the peer closes it (or it errors) before we answered in the
    /// notch, the request was resolved elsewhere — invoke `onClose` so the UI can dismiss its card.
    private func monitorClose(_ conn: NWConnection, held: HeldRequest, onClose: @escaping () -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            guard !held.isResolved else { return }       // our own response closed it — not a bail-out
            if isComplete || error != nil {
                conn.cancel()
                onClose()
            } else {
                self?.monitorClose(conn, held: held, onClose: onClose)   // spurious data; keep watching
            }
        }
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Parse the AskUserQuestion tool_input into structured questions + options for the notch UI.
    private static func parseClarificationQuestions(_ toolInput: [String: Any]) -> [ClarificationQuestion] {
        guard let qs = toolInput["questions"] as? [[String: Any]] else { return [] }
        return qs.map { q in
            let opts = (q["options"] as? [[String: Any]] ?? []).map {
                ClarificationOption(label: $0["label"] as? String ?? "",
                                    description: $0["description"] as? String ?? "")
            }
            return ClarificationQuestion(
                question: q["question"] as? String ?? "",
                header: q["header"] as? String ?? "",
                options: opts,
                multiSelect: q["multiSelect"] as? Bool ?? false)
        }
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
