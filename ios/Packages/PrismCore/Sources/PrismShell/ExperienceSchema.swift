import Foundation

public enum ExperienceSchema {
    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
    static let string: [String: Any] = ["type": "string"]
    static func nullable(_ schema: [String: Any]) -> [String: Any] { ["anyOf": [schema, ["type": "null"]]] }
    static func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    static func array(_ schema: [String: Any]) -> [String: Any] { ["type": "array", "items": schema] }
    public static var arguments: [String: Any] {
        object(["title": nullable(string), "body": nullable(string), "project": nullable(string), "topic": nullable(string),
                "query": nullable(string), "dueAt": nullable(["type": "string", "description": "ISO8601 date with UTC offset; clarify ambiguous local times"]),
                "seconds": nullable(["type": "integer"]), "sessionKind": nullable(enumeration(SessionKind.allCases.map(\.rawValue)))])
    }
    public static var schema: [String: Any] {
        let item = object(["label": string, "value": string, "actionID": nullable(string)])
        let scene = object(["kind": enumeration(SceneKind.allCases.map(\.rawValue)), "title": string, "body": string,
                            "items": array(item), "progress": nullable(["type": "number"]), "timerEnd": nullable(["type": "string"]),
                            "expiresInSeconds": ["type": "integer"]])
        let action = object(["id": string, "tool": enumeration(ToolName.allCases.map(\.rawValue)), "summary": string, "arguments": arguments])
        let artifact = object(["title": string, "body": string, "kind": enumeration(ArtifactKind.allCases.map(\.rawValue)),
                               "project": nullable(string), "topic": nullable(string)])
        let decision = object(["candidateID": string, "disposition": enumeration(["show", "phoneOnly", "suppress"]), "reason": string])
        return object(["version": ["type": "integer", "enum": [1]], "turn": object([
            "canonicalAnswer": string, "spokenResponse": nullable(string), "lensScene": scene, "proposedActions": array(action),
            "artifacts": array(artifact), "clarification": nullable(string), "project": nullable(string), "proactiveDecision": nullable(decision)
        ])])
    }
    public static func decode(_ data: Data, now: Date) throws -> ExperiencePlan {
        guard data.count <= 524_288 else { throw ShellError.invalid("Experience payload too large") }
        let value = try JSONSerialization.jsonObject(with: data)
        try validate(value, schema: schema, path: "plan")
        let plan = try ShellJSON.decoder().decode(ExperiencePlan.self, from: data)
        try plan.validate(now: now)
        return plan
    }
    /// Reject unknown fields locally as well as asking the provider for a strict schema.
    /// Nullable fields may be absent locally (Swift Codable omits nil); provider requires all keys.
    static func validate(_ value: Any, schema: [String: Any], path: String) throws {
        if let alternatives = schema["anyOf"] as? [[String: Any]] {
            for alternative in alternatives { if (try? validate(value, schema: alternative, path: path)) != nil { return } }
            throw ShellError.invalid("Invalid \(path)")
        }
        if let allowed = schema["enum"] as? [String], let s = value as? String, !allowed.contains(s) { throw ShellError.invalid("Unknown \(path)") }
        switch schema["type"] as? String {
        case "null": guard value is NSNull else { throw ShellError.invalid("Expected null: \(path)") }
        case "object":
            guard let object = value as? [String: Any], let properties = schema["properties"] as? [String: [String: Any]],
                  Set(object.keys).isSubset(of: Set(properties.keys)) else { throw ShellError.invalid("Unknown or invalid fields: \(path)") }
            for (key, property) in properties {
                if let v = object[key] { try validate(v, schema: property, path: path + "." + key) }
                else if property["anyOf"] == nil { throw ShellError.invalid("Missing \(path).\(key)") }
            }
        case "array":
            guard let array = value as? [Any], let item = schema["items"] as? [String: Any] else { throw ShellError.invalid("Expected list: \(path)") }
            guard array.count <= 128 else { throw ShellError.invalid("Too many values: \(path)") }
            for v in array { try validate(v, schema: item, path: path + "[]") }
        case "string": guard value is String else { throw ShellError.invalid("Expected text: \(path)") }
        case "number", "integer":
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw ShellError.invalid("Expected number: \(path)") }
            if schema["type"] as? String == "integer" && n.doubleValue.rounded() != n.doubleValue { throw ShellError.invalid("Expected integer: \(path)") }
        default: throw ShellError.invalid("Invalid schema")
        }
    }
}
import CoreFoundation
