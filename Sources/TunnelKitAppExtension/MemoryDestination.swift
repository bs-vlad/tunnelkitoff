

import Foundation
import SwiftyBeaver

/// Implements a `SwiftyBeaver.BaseDestination` logging to a memory buffer.
public class MemoryDestination: BaseDestination, CustomStringConvertible {
    private var buffer: [String] = []

    /// Max number of retained lines.
    public var maxLines: Int?

    public override init() {
        super.init()
        asynchronously = false
    }

    /**
     Starts logging. Optionally prepend an array of lines.

     - Parameter existing: The optional lines to prepend (none by default).
     **/
    public func start(with existing: [String] = []) {
        execute(synchronously: true) {
            self.buffer = existing
        }
    }

    /**
     Flushes the log content to an URL.
     
     - Parameter url: The URL to write the log content to.
     **/
    public func flush(to url: URL) {
        execute(synchronously: true) {
            let content = self.buffer.joined(separator: "\n")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: BaseDestination

    // XXX: executed in SwiftyBeaver queue. DO NOT invoke execute* here (sync in sync would crash otherwise)
    public override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String, file: String, function: String, line: Int, context: Any?) -> String? {
        guard let message = super.send(level, msg: msg, thread: thread, file: file, function: function, line: line) else {
            return nil
        }
        buffer.append(message)
        if let maxLines = maxLines {
            while buffer.count > maxLines {
                buffer.removeFirst()
            }
        }
        return message
    }

    // MARK: CustomStringConvertible

    public var description: String {
        return executeSynchronously {
            return self.buffer.joined(separator: "\n")
        }
    }
}
