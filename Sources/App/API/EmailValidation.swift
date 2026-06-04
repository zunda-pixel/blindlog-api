import Algorithms
import Foundation

func normalizeEmail(_ email: String) -> String {
  email.trimming(while: \.isWhitespace).lowercased()
}

func validatedEmail(_ email: String) -> String? {
  let normalizedEmail = normalizeEmail(email)
  guard normalizedEmail.count <= 254,
    normalizedEmail.range(
      of: #"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  else {
    return nil
  }
  return normalizedEmail
}
