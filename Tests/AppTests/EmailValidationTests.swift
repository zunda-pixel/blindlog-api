import Testing

@testable import App

struct EmailValidationTests {
  @Test
  func validatedEmailNormalizesValidEmail() {
    #expect(validatedEmail(" User+tag@Example.COM ") == "user+tag@example.com")
    #expect(validatedEmail("zunda.dev@gmail.com") == "zunda.dev@gmail.com")
    #expect(validatedEmail("user@example") == "user@example")
  }

  @Test
  func validatedEmailRejectsEmptyAndInvalidEmail() {
    for email in ["", "   ", "not-an-email", "user@", "@example.com"] {
      #expect(validatedEmail(email) == nil)
    }
  }
}
