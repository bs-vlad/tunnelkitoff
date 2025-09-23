import Foundation

public extension DispatchQueue {
    func schedule(after: DispatchTimeInterval, block: @escaping () -> Void) {
        asyncAfter(deadline: .now() + after, execute: block)
    }
}

public func fromDictionary<T: Decodable>(_ type: T.Type, _ dictionary: [String: Any]) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: dictionary, options: .fragmentsAllowed)
    return try JSONDecoder().decode(T.self, from: data)
}

public extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any] else {
            fatalError("JSONSerialization failed to encode")
        }
        return dictionary
    }
}

extension TimeInterval {
    public var asTimeString: String {
        var ticks = Int(self)
        let hours = ticks / 3600
        ticks %= 3600
        let minutes = ticks / 60
        let seconds = ticks % 60

        return [(hours, "h"), (minutes, "m"), (seconds, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
            .joined()
    }
}
