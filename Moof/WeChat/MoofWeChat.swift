import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import Observation

struct MoofWeChatCredential: Codable, Sendable {
    let token: String
    let accountID: String
    let userID: String
    let baseURL: URL
    let contextToken: String?
}

private enum MoofWeChatCredentialStore {
    private struct Failure: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private static func fileURL() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            assertionFailure("The user Application Support directory should exist.")
            throw Failure(message: "The Application Support directory is unavailable.")
        }
        return applicationSupport
            .appendingPathComponent("Moof", isDirectory: true)
            .appendingPathComponent("wechat-credential.json")
    }

    static func load() throws -> MoofWeChatCredential? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MoofWeChatCredential.self, from: data)
    }

    static func save(_ credential: MoofWeChatCredential) throws {
        let url = try fileURL()
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(credential)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var excludedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excludedURL.setResourceValues(values)
    }

    static func delete() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private enum MoofWeChatAPI {
    struct QRResponse: Decodable {
        let qrcode: String
        let qrcodeImage: String

        enum CodingKeys: String, CodingKey {
            case qrcode
            case qrcodeImage = "qrcode_img_content"
        }
    }

    struct StatusResponse: Decodable {
        let status: String
        let botToken: String?
        let botID: String?
        let baseURL: String?
        let userID: String?
        let redirectHost: String?

        enum CodingKeys: String, CodingKey {
            case status
            case botToken = "bot_token"
            case botID = "ilink_bot_id"
            case baseURL = "baseurl"
            case userID = "ilink_user_id"
            case redirectHost = "redirect_host"
        }
    }

    private struct SendMessageResponse: Decodable {
        let ret: Int?
        let errcode: Int?
        let errmsg: String?
    }

    private struct BaseInfo: Encodable {
        let channelVersion: String
        let botAgent: String

        enum CodingKeys: String, CodingKey {
            case channelVersion = "channel_version"
            case botAgent = "bot_agent"
        }

        init() {
            channelVersion = "3.0.0-beta-0"
            botAgent = "Moof/1.0.1"
        }
    }

    private struct SendMessageRequest: Encodable {

        struct TextItem: Encodable {
            let text: String
        }

        struct MessageItem: Encodable {
            let type: Int
            let textItem: TextItem

            enum CodingKeys: String, CodingKey {
                case type
                case textItem = "text_item"
            }

            init(text: String) {
                type = 1
                textItem = TextItem(text: text)
            }
        }

        struct Message: Encodable {
            let fromUserID: String
            let toUserID: String
            let clientID: String
            let messageType: Int
            let messageState: Int
            let itemList: [MessageItem]
            let contextToken: String?

            enum CodingKeys: String, CodingKey {
                case fromUserID = "from_user_id"
                case toUserID = "to_user_id"
                case clientID = "client_id"
                case messageType = "message_type"
                case messageState = "message_state"
                case itemList = "item_list"
                case contextToken = "context_token"
            }

            init(to userID: String, clientID: String, text: String, contextToken: String?) {
                fromUserID = ""
                toUserID = userID
                self.clientID = clientID
                messageType = 2
                messageState = 2
                itemList = [MessageItem(text: text)]
                self.contextToken = contextToken
            }
        }

        let msg: Message
        let baseInfo: BaseInfo

        enum CodingKeys: String, CodingKey {
            case msg
            case baseInfo = "base_info"
        }

        init(msg: Message) {
            self.msg = msg
            baseInfo = BaseInfo()
        }
    }

    enum Failure: LocalizedError {
        case invalidURL
        case invalidResponse
        case http(status: Int, detail: String)
        case server(String)
        case contextExpired
        case staleSession

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "WeChat returned an invalid server URL."
            case .invalidResponse:
                "WeChat returned an incomplete response."
            case .http(let status, let detail):
                detail.isEmpty ? "WeChat returned HTTP \(status)." : "WeChat returned HTTP \(status): \(detail)"
            case .server(let message):
                message
            case .contextExpired:
                "WeChat’s delivery context expired."
            case .staleSession:
                "WeChat requires re-verification. Reconnect WeChat to continue."
            }
        }
    }

    static func requestQRCode() async throws -> QRResponse {
        let body = try JSONEncoder().encode(["local_token_list": [String]()])
        let data = try await request(
            baseURL: URL(string: "https://ilinkai.weixin.qq.com")!,
            endpoint: "ilink/bot/get_bot_qrcode",
            queryItems: [URLQueryItem(name: "bot_type", value: "3")],
            method: "POST",
            body: body,
            timeout: 15
        )
        let response = try JSONDecoder().decode(QRResponse.self, from: data)
        guard !response.qrcode.isEmpty, !response.qrcodeImage.isEmpty else {
            throw Failure.invalidResponse
        }
        return response
    }

    static func pollStatus(baseURL: URL, qrcode: String, verifyCode: String?) async throws -> StatusResponse {
        var queryItems = [URLQueryItem(name: "qrcode", value: qrcode)]
        if let verifyCode, !verifyCode.isEmpty {
            queryItems.append(URLQueryItem(name: "verify_code", value: verifyCode))
        }
        let data = try await request(
            baseURL: baseURL,
            endpoint: "ilink/bot/get_qrcode_status",
            queryItems: queryItems,
            method: "GET",
            timeout: 35
        )
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    static func send(text: String, to userID: String, credential: MoofWeChatCredential) async throws {
        let clientID = "moof:\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString.prefix(8).lowercased())"
        let payload = SendMessageRequest(
            msg: .init(to: userID, clientID: clientID, text: text, contextToken: credential.contextToken)
        )
        let data = try await request(
            baseURL: credential.baseURL,
            endpoint: "ilink/bot/sendmessage",
            method: "POST",
            token: credential.token,
            body: try JSONEncoder().encode(payload),
            timeout: 15
        )
        let response = try JSONDecoder().decode(SendMessageResponse.self, from: data)
        let code = response.ret.flatMap { $0 == 0 ? nil : $0 } ?? response.errcode
        if let code, code != 0 {
            switch code {
            case -2:
                throw Failure.contextExpired
            case -14:
                throw Failure.staleSession
            default:
                throw Failure.server(response.errmsg ?? "WeChat send failed with code \(code).")
            }
        }
    }

    private static func request(
        baseURL: URL,
        endpoint: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        token: String? = nil,
        body: Data? = nil,
        timeout: TimeInterval
    ) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidURL
        }
        components.path = (components.path.hasSuffix("/") ? components.path : components.path + "/") + endpoint
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw Failure.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("bot", forHTTPHeaderField: "iLink-App-Id")
        request.setValue("196608", forHTTPHeaderField: "iLink-App-ClientVersion")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("ilink_bot_token", forHTTPHeaderField: "AuthorizationType")
            request.setValue(
                Data(String(UInt32.random(in: .min ... .max)).utf8).base64EncodedString(),
                forHTTPHeaderField: "X-WECHAT-UIN"
            )
        }
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = String(String(decoding: data, as: UTF8.self).prefix(300))
            throw Failure.http(status: httpResponse.statusCode, detail: detail)
        }
        return data
    }
}

@MainActor
@Observable
final class MoofWeChat {
    static let shared = MoofWeChat()

    enum Phase: Equatable {
        case idle
        case starting
        case scanning
        case scanned
        case pinRequired
        case pinRejected
        case verifying
        case connected
        case failed(String)
    }

    private(set) var credential: MoofWeChatCredential?
    private(set) var phase: Phase = .idle
    private(set) var qrImage: NSImage?
    private(set) var problem: String?
    var verificationCode = ""

    var mirrorNotifications: Bool {
        didSet {
            UserDefaults.standard.set(mirrorNotifications, forKey: "WeChatMirrorNotifications")
            if !mirrorNotifications {
                deliveryGeneration += 1
                queuedMessages.removeAll()
                deliveryTask?.cancel()
                deliveryTask = nil
            }
        }
    }

    var isPaired: Bool { credential != nil }

    var isConnected: Bool { credential != nil }

    var isLoggingIn: Bool {
        switch phase {
        case .starting, .scanning, .scanned, .pinRequired, .pinRejected, .verifying:
            true
        case .idle, .connected, .failed:
            false
        }
    }

    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var loginSessionID: UUID?
    @ObservationIgnored private var pendingVerificationCode: String?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var deliveryGeneration = 0
    @ObservationIgnored private var queuedMessages: [String] = []

    private init() {
        mirrorNotifications = UserDefaults.standard.bool(forKey: "WeChatMirrorNotifications")
        do {
            if let credential = try MoofWeChatCredentialStore.load() {
                self.credential = credential
                phase = .connected
            }
        } catch {
            let message = "The saved WeChat connection could not be read: \(error.localizedDescription)"
            problem = message
            phase = .failed(message)
        }
    }

    func beginLogin() {
        guard credential == nil else { return }
        loginTask?.cancel()
        let sessionID = UUID()
        loginSessionID = sessionID
        pendingVerificationCode = nil
        verificationCode = ""
        qrImage = nil
        problem = nil
        phase = .starting
        loginTask = Task { [weak self] in
            await self?.performLogin(sessionID: sessionID)
        }
    }

    func submitVerificationCode() {
        guard phase == .pinRequired || phase == .pinRejected else { return }
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        pendingVerificationCode = code
        verificationCode = ""
        phase = .verifying
    }

    func cancelLogin() {
        loginSessionID = nil
        loginTask?.cancel()
        loginTask = nil
        pendingVerificationCode = nil
        verificationCode = ""
        qrImage = nil
        if let credential {
            phase = .connected
        } else {
            phase = .idle
        }
    }

    func disconnect() {
        do {
            try MoofWeChatCredentialStore.delete()
        } catch {
            problem = "WeChat could not be disconnected: \(error.localizedDescription)"
            return
        }
        loginSessionID = nil
        loginTask?.cancel()
        loginTask = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        pendingVerificationCode = nil
        verificationCode = ""
        credential = nil
        mirrorNotifications = false
        qrImage = nil
        problem = nil
        phase = .idle
    }

    func send(_ notification: MoofNotification) {
        guard mirrorNotifications, credential != nil else { return }
        var text = notification.title + "\n" + notification.body
        if let source = notification.source, !source.isEmpty {
            text += "\n\n" + source
        }
        if let action = notification.action {
            text += "\n" + notification.actionTitle + ": " + action.absoluteString
        }
        enqueue(text)
    }

    func sendTestMessage() {
        guard credential != nil else { return }
        let emoji = ["🌙", "✨", "🍊", "🌿", "🫧", "🎈", "🐾", "🌸", "☀️", "🍀"]
        let sequence = (0..<Int.random(in: 3...6)).map { _ in
            emoji[Int.random(in: emoji.indices)]
        }.joined()
        enqueue(sequence)
    }

    private func enqueue(_ text: String) {
        queuedMessages.append(text)
        guard deliveryTask == nil else { return }
        deliveryGeneration += 1
        let generation = deliveryGeneration
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            deliveryLoop: while !Task.isCancelled, self.deliveryGeneration == generation {
                guard let credential = self.credential, !self.queuedMessages.isEmpty else {
                    break
                }
                let text = self.queuedMessages.removeFirst()
                do {
                    try await MoofWeChatAPI.send(text: text, to: credential.userID, credential: credential)
                    if self.deliveryGeneration == generation {
                        self.problem = nil
                    }
                } catch MoofWeChatAPI.Failure.contextExpired {
                    guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                    guard credential.contextToken != nil else {
                        self.problem = "WeChat send failed: \(MoofWeChatAPI.Failure.contextExpired.localizedDescription)"
                        continue
                    }
                    let contextless = MoofWeChatCredential(
                        token: credential.token,
                        accountID: credential.accountID,
                        userID: credential.userID,
                        baseURL: credential.baseURL,
                        contextToken: nil
                    )
                    do {
                        try await MoofWeChatAPI.send(text: text, to: contextless.userID, credential: contextless)
                        guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                        self.credential = contextless
                        do {
                            try MoofWeChatCredentialStore.save(contextless)
                            self.problem = nil
                        } catch {
                            self.problem = "WeChat delivered the message, but could not clear its expired context: \(error.localizedDescription)"
                        }
                    } catch {
                        guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                        self.problem = "WeChat send failed: \(error.localizedDescription)"
                    }
                } catch {
                    guard !Task.isCancelled, self.deliveryGeneration == generation else { return }
                    self.problem = "WeChat send failed: \(error.localizedDescription)"
                }
            }
            if self.deliveryGeneration == generation {
                self.deliveryTask = nil
                self.queuedMessages.removeAll()
            }
        }
    }

    private func performLogin(sessionID: UUID) async {
        defer {
            if loginSessionID == sessionID {
                loginSessionID = nil
                loginTask = nil
            }
        }

        do {
            var pollingBaseURL = URL(string: "https://ilinkai.weixin.qq.com")!
            var refreshCount = 1
            var response = try await MoofWeChatAPI.requestQRCode()
            try installQRCode(response.qrcodeImage, sessionID: sessionID)
            let deadline = Date().addingTimeInterval(480)

            while Date() < deadline {
                guard loginSessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
                let status: MoofWeChatAPI.StatusResponse
                do {
                    status = try await MoofWeChatAPI.pollStatus(
                        baseURL: pollingBaseURL,
                        qrcode: response.qrcode,
                        verifyCode: pendingVerificationCode
                    )
                } catch {
                    if Task.isCancelled || loginSessionID != sessionID { throw CancellationError() }
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                guard loginSessionID == sessionID, !Task.isCancelled else { throw CancellationError() }

                if status.status.contains("need_verifycode") {
                    if pendingVerificationCode != nil {
                        pendingVerificationCode = nil
                        verificationCode = ""
                        phase = .pinRejected
                    } else if phase != .pinRejected {
                        phase = .pinRequired
                    }
                    while pendingVerificationCode == nil {
                        guard loginSessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
                        guard Date() < deadline else {
                            throw MoofWeChatAPI.Failure.server("WeChat login timed out. Try again.")
                        }
                        try await Task.sleep(for: .milliseconds(150))
                    }
                    continue
                }

                switch status.status {
                case "wait":
                    break
                case "scaned":
                    if pendingVerificationCode != nil {
                        pendingVerificationCode = nil
                        verificationCode = ""
                    }
                    phase = .scanned
                case "scaned_but_redirect":
                    if let host = status.redirectHost, let redirectedURL = URL(string: "https://\(host)") {
                        pollingBaseURL = redirectedURL
                    }
                case "expired":
                    refreshCount += 1
                    guard refreshCount <= 3 else {
                        throw MoofWeChatAPI.Failure.server("The QR code expired too many times. Try again.")
                    }
                    response = try await MoofWeChatAPI.requestQRCode()
                    try installQRCode(response.qrcodeImage, sessionID: sessionID)
                    pendingVerificationCode = nil
                    verificationCode = ""
                case "verify_code_blocked":
                    refreshCount += 1
                    guard refreshCount <= 3 else {
                        throw MoofWeChatAPI.Failure.server("Too many incorrect PIN attempts. Try again later.")
                    }
                    response = try await MoofWeChatAPI.requestQRCode()
                    try installQRCode(response.qrcodeImage, sessionID: sessionID)
                    pendingVerificationCode = nil
                    verificationCode = ""
                case "binded_redirect":
                    throw MoofWeChatAPI.Failure.server("This WeChat bot is already paired. Reset the pairing, then try again.")
                case "confirmed":
                    guard
                        let token = status.botToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                        !token.isEmpty,
                        let accountID = status.botID?.trimmingCharacters(in: .whitespacesAndNewlines),
                        !accountID.isEmpty,
                        let userID = status.userID?.trimmingCharacters(in: .whitespacesAndNewlines),
                        !userID.isEmpty
                    else {
                        throw MoofWeChatAPI.Failure.invalidResponse
                    }
                    let baseURL: URL
                    if let raw = status.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                        guard
                            let url = URL(string: raw),
                            ["http", "https"].contains(url.scheme?.lowercased()),
                            url.host != nil
                        else {
                            throw MoofWeChatAPI.Failure.invalidResponse
                        }
                        baseURL = url
                    } else {
                        baseURL = pollingBaseURL
                    }
                    let credential = MoofWeChatCredential(
                        token: token,
                        accountID: accountID,
                        userID: userID,
                        baseURL: baseURL,
                        contextToken: nil
                    )
                    try MoofWeChatCredentialStore.save(credential)
                    self.credential = credential
                    pendingVerificationCode = nil
                    verificationCode = ""
                    qrImage = nil
                    problem = nil
                    phase = .connected
                    return
                default:
                    throw MoofWeChatAPI.Failure.invalidResponse
                }

                try await Task.sleep(for: .seconds(1))
            }
            throw MoofWeChatAPI.Failure.server("WeChat login timed out. Try again.")
        } catch is CancellationError {
            return
        } catch {
            guard loginSessionID == sessionID else { return }
            pendingVerificationCode = nil
            verificationCode = ""
            qrImage = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func installQRCode(_ value: String, sessionID: UUID) throws {
        guard loginSessionID == sessionID else { throw CancellationError() }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            assertionFailure("Core Image should generate a QR code for the login URL.")
            throw MoofWeChatAPI.Failure.invalidResponse
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        qrImage = image
        phase = .scanning
    }
}
