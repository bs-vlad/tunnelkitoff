import Foundation

extension NSRegularExpression {
    public convenience init(_ pattern: String) {
        try! self.init(pattern: pattern, options: [])
    }

    public func groups(in string: String) -> [String] {
        var results: [String] = []
        enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: string.count)) { result, _, _ in
            guard let result = result else {
                return
            }
            for i in 0..<numberOfCaptureGroups {
                let subrange = result.range(at: i + 1)
                let match = (string as NSString).substring(with: subrange)
                results.append(match)
            }
        }
        return results
    }
}

extension NSRegularExpression {
    public func enumerateSpacedComponents(in string: String, using block: ([String]) -> Void) {
        enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: string.count)) { result, _, _ in
            guard let range = result?.range else {
                return
            }
            let match = (string as NSString).substring(with: range)
            let tokens = match.components(separatedBy: " ").filter { !$0.isEmpty }
            block(tokens)
        }
    }

    public func enumerateSpacedArguments(in string: String, using block: ([String]) -> Void) {
        enumerateSpacedComponents(in: string) { (tokens) in
            var args = tokens
            args.removeFirst()
            block(args)
        }
    }
}
