import Foundation
import os.log
import SwiftyBeaver

public final class TKLogger {

    public static let shared = TKLogger()
    private let log = SwiftyBeaver.self

      private init() {
          let customDestination = CustomLogDestination()
          log.addDestination(customDestination)
      }

      public func addDestination(_ destination: BaseDestination) {
          log.addDestination(destination)
      }

      public func debug(_ message: @autoclosure () -> Any,
                        file: String = #file,
                        function: String = #function,
                        line: Int = #line) {
          log.debug(message(), file, function, line: line)
      }

      public func error(_ message: @autoclosure () -> Any,
                        file: String = #file,
                        function: String = #function,
                        line: Int = #line) {
          log.error(message(), file, function, line: line)
      }

      public func info(_ message: @autoclosure () -> Any,
                       file: String = #file,
                       function: String = #function,
                       line: Int = #line) {
          log.info(message(), file, function, line: line)
      }

      public func warning(_ message: @autoclosure () -> Any,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
          log.warning(message(), file, function, line: line)
      }

      public func verbose(_ message: @autoclosure () -> Any,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
          log.verbose(message(), file, function, line: line)
      }

      public func setLogCallback(_ callback: @escaping (Date, String, Bool, SwiftyBeaver.Level) -> Void) {
          CustomLogDestination.logCallback = callback
      }

      private class CustomLogDestination: BaseDestination {
          static var logCallback: ((Date, String, Bool, SwiftyBeaver.Level) -> Void)?

          override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                             file: String, function: String, line: Int, context: Any?) -> String? {
              let timestamp = Date()
              let isError = level == .error

              CustomLogDestination.logCallback?(timestamp, msg, isError, level)

              return super.send(level, msg: msg, thread: thread, file: file,
                                function: function, line: line, context: context)
          }
      }
  }


