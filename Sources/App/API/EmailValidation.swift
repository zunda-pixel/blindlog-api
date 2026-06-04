import Algorithms
import Foundation

func normalizeEmail(_ email: String) -> String {
  email.trimming(while: \.isWhitespace).lowercased()
}

func validatedEmail(_ email: String) -> String? {
  let normalizedEmail = normalizeEmail(email)
  // https://html.spec.whatwg.org/multipage/input.html#email-state-(type=email)
  let emailRegex = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
  guard
    normalizedEmail.range(
      of: emailRegex,
      options: .regularExpression
    ) != nil
  else {
    return nil
  }
  return normalizedEmail
}
