import Foundation
import Observation

struct MoofTelegramCredential: Codable {
    let token: String
    let botID: Int64
    let botUsername: String
    let chatID: Int64
    let chatName: String
}

private enum MoofTelegramCredentialStore {
    private static let key = "TelegramCredential"

    static func load() -> MoofTelegramCredential? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MoofTelegramCredential.self, from: data)
    }

    static func save(_ credential: MoofTelegramCredential) {
        guard let data = try? JSONEncoder().encode(credential) else {
            assertionFailure("Telegram credentials are Codable and must encode.")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private enum MoofTelegramAPI {
    struct Bot: Decodable {
        let id: Int64
        let isBot: Bool
        let username: String?

        enum CodingKeys: String, CodingKey {
            case id
            case isBot = "is_bot"
            case username
        }
    }

    struct Update: Decodable {
        let updateID: Int64
        let message: Message?

        enum CodingKeys: String, CodingKey {
            case updateID = "update_id"
            case message
        }
    }

    struct Message: Decodable {
        let from: User?
        let chat: Chat
        let text: String?
    }

    struct User: Decodable {
        let isBot: Bool

        enum CodingKeys: String, CodingKey {
            case isBot = "is_bot"
        }
    }

    struct Chat: Decodable {
        let id: Int64
        let type: String
        let title: String?
        let firstName: String?
        let lastName: String?
        let username: String?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case title
            case firstName = "first_name"
            case lastName = "last_name"
            case username
        }
    }

    enum Failure: LocalizedError {
        case invalidToken
        case invalidResponse
        case response(status: Int, message: String, retryAfter: Int?)

        var errorDescription: String? {
            switch self {
            case .invalidToken:
                "The bot token is not valid."
            case .invalidResponse:
                "Telegram returned an incomplete response."
            case .response(_, let message, _):
                message.isEmpty ? "Telegram rejected the request." : message
            }
        }

        var isRateLimited: Bool {
            if case .response(429, _, _) = self { true } else { false }
        }

        var retryAfter: Int? {
            if case .response(_, _, let retryAfter) = self { retryAfter } else { nil }
        }

        var isRetryable: Bool {
            switch self {
            case .response(let status, _, _):
                status == 408 || status == 429 || status >= 500
            case .invalidResponse:
                true
            case .invalidToken:
                false
            }
        }

        var tokenRejected: Bool {
            if case .response(401, _, _) = self { true } else { false }
        }
    }

    private struct Envelope<Result: Decodable>: Decodable {
        struct Parameters: Decodable {
            let retryAfter: Int?

            enum CodingKeys: String, CodingKey {
                case retryAfter = "retry_after"
            }
        }

        let ok: Bool
        let result: Result?
        let description: String?
        let parameters: Parameters?
    }

    private struct SentMessage: Decodable {
        let messageID: Int64

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
        }
    }

    private struct LinkPreviewOptions: Encodable {
        let isDisabled = true

        enum CodingKeys: String, CodingKey {
            case isDisabled = "is_disabled"
        }
    }

    private struct InlineButton: Encodable {
        let text: String
        let url: String
    }

    private struct ReplyMarkup: Encodable {
        let inlineKeyboard: [[InlineButton]]

        enum CodingKeys: String, CodingKey {
            case inlineKeyboard = "inline_keyboard"
        }
    }

    private struct SendMessage: Encodable {
        let chatID: Int64
        let text: String
        let linkPreviewOptions = LinkPreviewOptions()
        let replyMarkup: ReplyMarkup?

        enum CodingKeys: String, CodingKey {
            case chatID = "chat_id"
            case text
            case linkPreviewOptions = "link_preview_options"
            case replyMarkup = "reply_markup"
        }

        init(chatID: Int64, text: String, action: URL?, actionTitle: String) {
            self.chatID = chatID
            self.text = text
            replyMarkup = action.map {
                ReplyMarkup(inlineKeyboard: [[InlineButton(text: actionTitle, url: $0.absoluteString)]])
            }
        }
    }

    static func bot(token: String) async throws -> Bot {
        let bot: Bot = try await request(token: token, method: "getMe", timeout: 15)
        guard bot.isBot, let username = bot.username, !username.isEmpty else {
            throw Failure.invalidResponse
        }
        return bot
    }

    static func nextUpdateOffset(token: String) async throws -> Int64 {
        let updates: [Update] = try await request(
            token: token,
            method: "getUpdates",
            queryItems: [
                URLQueryItem(name: "offset", value: "-1"),
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "timeout", value: "0"),
            ],
            timeout: 15
        )
        return updates.last.map { $0.updateID + 1 } ?? 0
    }

    static func updates(token: String, offset: Int64) async throws -> [Update] {
        try await request(
            token: token,
            method: "getUpdates",
            queryItems: [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "timeout", value: "25"),
                URLQueryItem(name: "allowed_updates", value: "[\"message\"]"),
            ],
            timeout: 35
        )
    }

    static func send(
        token: String,
        chatID: Int64,
        text: String,
        action: URL?,
        actionTitle: String
    ) async throws {
        let body = try JSONEncoder().encode(
            SendMessage(chatID: chatID, text: text, action: action, actionTitle: actionTitle)
        )
        let _: SentMessage = try await request(
            token: token,
            method: "sendMessage",
            body: body,
            timeout: 15
        )
    }

    private static func request<Result: Decodable>(
        token: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval
    ) async throws -> Result {
        guard
            var components = URLComponents(string: "https://api.telegram.org/bot\(token)/\(method)"),
            components.host != nil
        else {
            throw Failure.invalidToken
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw Failure.invalidToken }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        } else {
            request.httpMethod = "GET"
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        let envelope = try? JSONDecoder().decode(Envelope<Result>.self, from: data)
        if let envelope, envelope.ok, let result = envelope.result {
            return result
        }

        let detail = envelope?.description ?? String(decoding: data.prefix(300), as: UTF8.self)
        throw Failure.response(
            status: response.statusCode,
            message: detail,
            retryAfter: envelope?.parameters?.retryAfter
        )
    }
}

@MainActor
@Observable
final class MoofTelegram {
    static let shared = MoofTelegram()

    enum Phase: Equatable {
        case idle
        case validating
        case awaitingCode(botUsername: String, pairingCode: String)
        case connected
        case failed(String)
    }

    private struct Outgoing {
        let text: String
        let action: URL?
        let actionTitle: String
    }

    private(set) var credential: MoofTelegramCredential?
    private(set) var phase: Phase = .idle
    private(set) var problem: String?

    var mirrorNotifications: Bool {
        didSet {
            UserDefaults.standard.set(mirrorNotifications, forKey: "TelegramMirrorNotifications")
            if mirrorNotifications {
                startDeliveryIfPossible()
            } else {
                cancelDelivery()
            }
        }
    }

    var isConnected: Bool { credential != nil }

    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var pairingSessionID: UUID?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var deliveryGeneration = 0
    @ObservationIgnored private var queuedMessages: [Outgoing] = []

    private init() {
        let savedMirror = UserDefaults.standard.bool(forKey: "TelegramMirrorNotifications")
        if let credential = MoofTelegramCredentialStore.load() {
            self.credential = credential
            phase = .connected
            mirrorNotifications = savedMirror
        } else {
            mirrorNotifications = false
            if savedMirror {
                UserDefaults.standard.set(false, forKey: "TelegramMirrorNotifications")
            }
        }
    }

    func connect(botToken rawToken: String) {
        guard credential == nil else { return }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            phase = .failed("Enter a bot token.")
            return
        }

        let sessionID = UUID()
        pairingSessionID = sessionID
        pairingTask?.cancel()
        phase = .validating
        problem = nil
        pairingTask = Task { [weak self] in
            await self?.performPairing(token: token, sessionID: sessionID)
        }
    }

    func cancelPairing() {
        pairingSessionID = nil
        pairingTask?.cancel()
        pairingTask = nil
        phase = credential == nil ? .idle : .connected
    }

    func disconnect() {
        MoofTelegramCredentialStore.delete()
        pairingSessionID = nil
        pairingTask?.cancel()
        pairingTask = nil
        cancelDelivery()
        credential = nil
        mirrorNotifications = false
        problem = nil
        phase = .idle
    }

    func send(_ notification: MoofNotification) {
        guard mirrorNotifications, credential != nil else { return }

        var text = "\(notification.title)\n\(notification.body)"
        if let source = notification.source, !source.isEmpty {
            text += "\n\n\(source)"
        }

        var action: URL?
        if let url = notification.action {
            if ["http", "https", "tg"].contains(url.scheme?.lowercased() ?? "") {
                action = url
            } else {
                text += "\n\(notification.actionTitle): \(url.absoluteString)"
            }
        }

        let limit = 4_096
        if text.utf16.count > limit {
            var result = ""
            var units = 0
            for character in text {
                let width = String(character).utf16.count
                guard units + width + 1 <= limit else { break }
                result.append(character)
                units += width
            }
            text = result + "…"
        }

        enqueue(
            Outgoing(
                text: text,
                action: action,
                actionTitle: String(notification.actionTitle.prefix(64))
            )
        )
    }

    func sendTestMessage() {
        guard credential != nil else { return }
        enqueue(
            Outgoing(
                text: MoofTestMessage.randomEmoji,
                action: nil,
                actionTitle: "Open"
            )
        )
    }

    private func enqueue(_ message: Outgoing) {
        guard credential != nil else { return }
        queuedMessages.append(message)
        startDeliveryIfPossible()
    }

    private func startDeliveryIfPossible() {
        guard deliveryTask == nil, credential != nil, queuedMessages.first != nil else { return }

        deliveryGeneration += 1
        let generation = deliveryGeneration
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            var transientFailures = 0

            while !Task.isCancelled, self.deliveryGeneration == generation {
                guard let credential = self.credential, let message = self.queuedMessages.first else {
                    break
                }

                do {
                    try await MoofTelegramAPI.send(
                        token: credential.token,
                        chatID: credential.chatID,
                        text: message.text,
                        action: message.action,
                        actionTitle: message.actionTitle
                    )
                    guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                    self.queuedMessages.removeFirst()
                    self.problem = nil
                    transientFailures = 0
                    if !self.queuedMessages.isEmpty {
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch let failure as MoofTelegramAPI.Failure {
                    guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                    if failure.isRateLimited {
                        self.problem = "Telegram is rate limiting messages. Retrying…"
                        do {
                            try await Task.sleep(for: .seconds(failure.retryAfter ?? 5))
                        } catch {
                            return
                        }
                    } else if failure.isRetryable {
                        transientFailures += 1
                        self.problem = "Telegram send failed: \(failure.localizedDescription)"
                        let delay = min(pow(2, Double(transientFailures)), 30)
                        do {
                            try await Task.sleep(for: .seconds(delay))
                        } catch {
                            return
                        }
                    } else {
                        self.queuedMessages.removeAll()
                        self.problem =
                            failure.tokenRejected
                            ? "Telegram rejected the bot token. Reconnect Telegram."
                            : "Telegram send failed: \(failure.localizedDescription)"
                        break
                    }
                } catch {
                    guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                    if (error as? URLError)?.code == .cancelled { return }
                    transientFailures += 1
                    self.problem = "Telegram send failed: \(error.localizedDescription)"
                    let delay = min(pow(2, Double(transientFailures)), 30)
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                }
            }

            if self.deliveryGeneration == generation {
                self.deliveryTask = nil
            }
        }
    }

    private func cancelDelivery() {
        deliveryGeneration += 1
        queuedMessages.removeAll()
        deliveryTask?.cancel()
        deliveryTask = nil
    }

    private func performPairing(token: String, sessionID: UUID) async {
        defer {
            if pairingSessionID == sessionID {
                pairingSessionID = nil
                pairingTask = nil
            }
        }

        do {
            let bot = try await MoofTelegramAPI.bot(token: token)
            guard let username = bot.username, !username.isEmpty else {
                throw MoofTelegramAPI.Failure.invalidResponse
            }
            var offset = try await MoofTelegramAPI.nextUpdateOffset(token: token)
            guard pairingSessionID == sessionID, !Task.isCancelled else { return }
            let pairingCode = String(
                format: "%04X-%04X",
                UInt16.random(in: .min ... .max),
                UInt16.random(in: .min ... .max)
            )
            phase = .awaitingCode(botUsername: username, pairingCode: pairingCode)

            let deadline = Date().addingTimeInterval(300)
            var consecutiveFailures = 0
            while Date() < deadline {
                do {
                    let updates = try await MoofTelegramAPI.updates(token: token, offset: offset)
                    guard pairingSessionID == sessionID, !Task.isCancelled else { return }
                    consecutiveFailures = 0

                    for update in updates {
                        offset = max(offset, update.updateID + 1)
                        guard
                            let message = update.message,
                            message.from?.isBot == false,
                            message.chat.type == "private",
                            message.text?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased() == pairingCode
                        else { continue }

                        let fullName = [message.chat.firstName, message.chat.lastName]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        let chatName: String
                        if let title = message.chat.title, !title.isEmpty {
                            chatName = title
                        } else if !fullName.isEmpty {
                            chatName = fullName
                        } else if let username = message.chat.username, !username.isEmpty {
                            chatName = "@\(username)"
                        } else {
                            chatName = String(message.chat.id)
                        }

                        let credential = MoofTelegramCredential(
                            token: token,
                            botID: bot.id,
                            botUsername: username,
                            chatID: message.chat.id,
                            chatName: chatName
                        )
                        MoofTelegramCredentialStore.save(credential)
                        self.credential = credential
                        problem = nil
                        phase = .connected
                        do {
                            try await MoofTelegramAPI.send(
                                token: token,
                                chatID: message.chat.id,
                                text: "Moof connected\nThis chat is now paired with Moof.",
                                action: nil,
                                actionTitle: "Open"
                            )
                        } catch {
                            guard !Task.isCancelled else { return }
                            problem = "Telegram is connected, but the confirmation message could not be sent: \(error.localizedDescription)"
                        }
                        return
                    }
                } catch let failure as MoofTelegramAPI.Failure where failure.isRetryable {
                    guard pairingSessionID == sessionID, !Task.isCancelled else { return }
                    consecutiveFailures += 1
                    if consecutiveFailures >= 5 { throw failure }
                    try await Task.sleep(for: .seconds(2))
                } catch let failure as MoofTelegramAPI.Failure {
                    throw failure
                } catch {
                    guard pairingSessionID == sessionID, !Task.isCancelled else { return }
                    consecutiveFailures += 1
                    if consecutiveFailures >= 5 { throw error }
                    try await Task.sleep(for: .seconds(2))
                }
            }

            throw MoofTelegramAPI.Failure.response(
                status: 408,
                message: "Timed out waiting for Start in Telegram. Try again.",
                retryAfter: nil
            )
        } catch is CancellationError {
            return
        } catch let failure as MoofTelegramAPI.Failure {
            guard pairingSessionID == sessionID else { return }
            switch failure {
            case .invalidToken:
                phase = .failed("The bot token is not valid.")
            case .invalidResponse:
                phase = .failed("Telegram returned an incomplete response. Try again.")
            case .response(let status, _, _) where status == 401:
                phase = .failed("Telegram rejected this bot token. Check it with @BotFather.")
            case .response(let status, _, _) where status == 409:
                phase = .failed("This bot is already using a webhook or another update reader. Use an unused bot or remove the webhook.")
            case .response:
                phase = .failed(failure.localizedDescription)
            }
        } catch {
            guard pairingSessionID == sessionID else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
