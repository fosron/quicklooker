// Fixture for the Swift lexer
import Foundation

struct Greeter {
    let name: String

    func greet() -> String {
        let count = 3
        if count > 2 {
            return "Hello, \(name)!"
        }
        return ""
    }
}
