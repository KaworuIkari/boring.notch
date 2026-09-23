//
//  ClaudeCodeMonitor.swift
//  boringNotch
//
//  Listens for activity reports from Claude Code hooks and exposes them to the pet.
//

import Foundation
import Network
import SwiftUI

/// What Claude Code is doing right now.
enum ClaudeCodeActivity: String, Codable, CaseIterable {
    /// Nothing running, or we haven't heard anything in a while.
    case idle
    /// Claude is thinking or running tools.
    case working
    /// Claude needs the user: a permission prompt or a question.
    case waiting
    /// Claude just finished a turn. Shown briefly, then back to idle.
    case done
}

/// Receives state updates on a loopback-only socket.
///
/// The app is sandboxed, so it can't read a file that a hook script writes elsewhere in the
/// home folder. A local port sidesteps that: the hook is a one-line `curl`. Nothing but
/// 127.0.0.1 can reach it, and the only thing a message can do is change which cartoon is drawn.
@MainActor
final class ClaudeCodeMonitor: ObservableObject {
    static let shared = ClaudeCodeMonitor()

    /// Pick something unlikely to clash. Change it here and in the hook script together.
    static let port: UInt16 = 51748

    @Published private(set) var activity: ClaudeCodeActivity = .idle
    /// Optional short text from the hook, e.g. which tool is running.
    @Published private(set) var detail: String = ""
    @Published private(set) var isListening: Bool = false

    /// `done` is a celebration, not a resting state.
    private let doneDuration: Duration = .seconds(6)
    /// If Claude Code dies mid-turn we never hear about it, so stop believing `working` eventually.
    private let workingTimeout: Duration = .seconds(15 * 60)

    private var listener: NWListener?
    private var expiryTask: Task<Void, Never>?

    private struct Report: Decodable {
        let state: String
        let detail: String?
    }

    private init() {}

    // MARK: - Listening

    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback only: nothing outside this Mac can connect.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(rawValue: Self.port)!)

        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                    case .failed(let error):
                        NSLog("ClaudeCodeMonitor: listener failed: \(error)")
                        self?.isListening = false
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { connection in
                Self.handle(connection)
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            NSLog("ClaudeCodeMonitor: could not listen on port \(Self.port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        expiryTask?.cancel()
        activity = .idle
    }

    private nonisolated static func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            defer {
                // Always answer, so curl exits straight away instead of waiting.
                let response = Data("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                ClaudeCodeMonitor.shared.apply(request: request)
            }
        }
    }

    /// Pulls the JSON body out of a small HTTP request.
    private func apply(request: String) {
        guard let separator = request.range(of: "\r\n\r\n") else { return }
        let body = String(request[separator.upperBound...])
        guard let payload = try? JSONDecoder().decode(Report.self, from: Data(body.utf8)),
              let newActivity = ClaudeCodeActivity(rawValue: payload.state.lowercased())
        else { return }

        report(newActivity, detail: payload.detail ?? "")
    }

    // MARK: - State

    /// Also callable from the settings screen to preview each state.
    func report(_ newActivity: ClaudeCodeActivity, detail: String = "") {
        expiryTask?.cancel()
        expiryTask = nil

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            activity = newActivity
        }
        self.detail = detail

        switch newActivity {
        case .done:
            scheduleReturnToIdle(after: doneDuration)
        case .working, .waiting:
            scheduleReturnToIdle(after: workingTimeout)
        case .idle:
            break
        }
    }

    private func scheduleReturnToIdle(after duration: Duration) {
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self?.activity = .idle
            }
            self?.detail = ""
        }
    }
}
