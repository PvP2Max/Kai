import Foundation

// MARK: - AnyCodable Type for Dynamic JSON

/// A type-erased Codable value that can hold any JSON-compatible type.
struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode AnyCodable"))
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Chat Models

/// Request model for sending a chat message to Kai.
/// Matches the backend ChatRequest schema.
/// Note: APIClient uses `.convertFromSnakeCase`/`.convertToSnakeCase` so no CodingKeys needed.
struct ChatRequest: Codable, Sendable {
    /// The user's message text
    let message: String

    /// Optional conversation ID to continue an existing conversation
    let conversationId: UUID?

    /// Source of the message (e.g., "ios", "siri", "web")
    let source: ChatSource

    init(message: String, conversationId: UUID? = nil, source: ChatSource = .ios) {
        self.message = message
        self.conversationId = conversationId
        self.source = source
    }
}

/// Source platform for chat messages
enum ChatSource: String, Codable, Sendable {
    case ios
    case siri
    case web
    case watch
}

/// Response model from a chat message.
/// Matches the backend ChatResponse schema.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ChatResponse: Codable, Sendable {
    /// The assistant's response text
    let response: String

    /// The conversation ID (new or existing)
    let conversationId: UUID?

    /// Actions taken by the assistant during processing
    let actionsTaken: [ActionTaken]?

    /// Information about the model(s) used
    let modelInfo: ModelInfo?

    /// Non-optional accessor for actions taken (returns empty array if nil)
    var actions: [ActionTaken] {
        actionsTaken ?? []
    }
}

/// Represents an action taken by Kai during message processing.
/// Matches the backend ActionTaken schema.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ActionTaken: Codable, Equatable, Sendable {
    /// Name of the tool that was called
    let toolName: String

    /// Input parameters passed to the tool
    let toolInput: [String: AnyCodable]

    /// Result returned by the tool
    let result: AnyCodable

    /// Whether the tool execution was successful
    let success: Bool
}

/// Information about the model(s) used to generate a response.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ModelInfo: Codable, Equatable, Sendable {
    /// Primary model used
    let model: String?

    /// Cost information (if available)
    let cost: Double?

    /// Token usage information
    let inputTokens: Int?
    let outputTokens: Int?

    /// Processing time in milliseconds
    let processingTimeMs: Int?

    init(
        model: String? = nil,
        cost: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        processingTimeMs: Int? = nil
    ) {
        self.model = model
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.processingTimeMs = processingTimeMs
    }
}

// MARK: - Convenience Extensions

extension ChatResponse {
    /// Returns a summary of actions taken for display purposes
    var actionsSummary: String? {
        guard !actions.isEmpty else { return nil }

        let successfulActions = actions.filter { $0.success }
        if successfulActions.isEmpty { return nil }

        let actionNames = successfulActions.map { $0.toolName.replacingOccurrences(of: "_", with: " ") }
        return actionNames.joined(separator: ", ")
    }
}
