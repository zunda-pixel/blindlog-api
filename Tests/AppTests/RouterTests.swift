import Foundation
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import App

struct TestArguments: AppArguments {
  var hostname: String = "127.0.0.1"
  var port: Int = 8080
  var logLevel: Logger.Level? = .debug
  var env: EnvironmentLevel = .develop
  var rateLimitDurationSeconds: Int? = 3600
  var rateLimitIPAddressMaxCount: Int? = 100
  var rateLimitUserTokenMaxCount: Int? = 200
}

@Suite(.serialized)
struct RouterTests {
  @Test
  func health() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let response = try await client.execute(
        uri: "/health",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(response.status == .ok)
    }
  }

  @Test
  func wellKnownAppleAppSiteAssociation() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let response = try await client.execute(
        uri: "/.well-known/apple-app-site-association",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(response.status == .ok)
    }
  }

  @Test
  func createUser() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )
      let profileResponse = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["name": "Alice"]))
      )
      #expect(profileResponse.status == .ok)
      let createdProfile = try JSONDecoder().decode(
        Components.Schemas.UserProfile.self,
        from: profileResponse.body
      )

      // 2. Get latest user profile
      let getResponse = try await client.execute(
        uri: "/me",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )

      #expect(getResponse.status == .ok)
      let getProfile = try JSONDecoder().decode(
        Components.Schemas.Me.self,
        from: getResponse.body
      )
      #expect(getProfile.userID == newUser.userID)
      #expect(getProfile.userProfile?.name == "Alice")
      #expect(getProfile.userProfile?.createdAt == createdProfile.createdAt)
      #expect(getProfile.emails.isEmpty)
    }
  }

  @Test
  func userProfileRequiresAuthentication() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let getResponse = try await client.execute(
        uri: "/user_profile/\(UUID().uuidString)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(getResponse.status == .unauthorized)

      let postResponse = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["name": "Alice"]))
      )
      #expect(postResponse.status == .unauthorized)
    }
  }

  @Test
  func userProfileCreateAndGetLatest() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      let missingMeResponse = try await client.execute(
        uri: "/me",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )
      #expect(missingMeResponse.status == .ok)
      let missingMe = try JSONDecoder().decode(
        Components.Schemas.Me.self,
        from: missingMeResponse.body
      )
      #expect(missingMe.userID == newUser.userID)
      #expect(missingMe.userProfile == nil)
      #expect(missingMe.emails.isEmpty)

      let missingResponse = try await client.execute(
        uri: "/user_profile/\(newUser.userID)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )
      #expect(missingResponse.status == .notFound)

      let firstProfile = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["name": " Alice "]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.UserProfile.self, from: response.body)
      }
      #expect(firstProfile.userID == newUser.userID)
      #expect(firstProfile.name == "Alice")
      #expect(firstProfile.imageURL == nil)

      let secondProfile = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["name": "Bob"]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.UserProfile.self, from: response.body)
      }
      #expect(firstProfile.id != secondProfile.id)
      #expect(secondProfile.name == "Bob")
      #expect(secondProfile.imageURL == nil)

      try await client.execute(
        uri: "/user_profile/\(newUser.userID)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        let profile = try JSONDecoder().decode(
          Components.Schemas.UserProfile.self,
          from: response.body
        )
        #expect(profile.id == secondProfile.id)
        #expect(profile.name == "Bob")
        #expect(profile.imageURL == nil)
      }
    }
  }

  @Test
  func userProfileCanReferenceOwnImage() async throws {
    let arguments = TestArguments()
    let recorder = TestCloudflareImagesCallRecorder()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient(recorder: recorder)
    )
    let ipAddress = UUID().uuidString
    let cloudflareImageID = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      let image = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": cloudflareImageID]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.Image.self, from: response.body)
      }

      let profile = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(
          data: JSONEncoder().encode([
            "name": "Alice",
            "imageID": image.id,
          ])
        )
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.UserProfile.self, from: response.body)
      }
      #expect(
        profile.imageURL == "https://imagedelivery.net/account-hash/\(cloudflareImageID)/public")
      #expect(await recorder.imageURLCount == 1)

      try await client.execute(
        uri: "/user_profile/\(newUser.userID)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        let latestProfile = try JSONDecoder().decode(
          Components.Schemas.UserProfile.self,
          from: response.body
        )
        #expect(latestProfile.id == profile.id)
        #expect(
          latestProfile.imageURL
            == "https://imagedelivery.net/account-hash/\(cloudflareImageID)/public")
      }
      #expect(await recorder.imageURLCount == 1)

      try await client.execute(
        uri: "/user_profile/\(newUser.userID)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        let latestProfile = try JSONDecoder().decode(
          Components.Schemas.UserProfile.self,
          from: response.body
        )
        #expect(latestProfile.id == profile.id)
        #expect(
          latestProfile.imageURL
            == "https://imagedelivery.net/account-hash/\(cloudflareImageID)/public")
      }
      #expect(await recorder.imageURLCount == 1)
    }
  }

  @Test
  func userProfileRejectsOtherUsersImage() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient()
    )
    let ipAddress = UUID().uuidString
    let cloudflareImageID = UUID().uuidString

    try await app.test(.router) { client in
      let firstUser = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.UserToken.self, from: response.body)
      }
      let secondUser = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.UserToken.self, from: response.body)
      }

      let image = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(firstUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": cloudflareImageID]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.Image.self, from: response.body)
      }

      let response = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(secondUser.token)",
        ],
        body: ByteBuffer(
          data: JSONEncoder().encode([
            "name": "Bob",
            "imageID": image.id,
          ])
        )
      )
      #expect(response.status == .badRequest)
    }
  }

  @Test
  func userProfileValidatesName() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      for invalidName in ["", "   ", String(repeating: "a", count: 101)] {
        let response = try await client.execute(
          uri: "/me",
          method: .post,
          headers: [
            .cfConnectingIP: ipAddress,
            .authorization: "Bearer \(newUser.token)",
          ],
          body: ByteBuffer(data: JSONEncoder().encode(["name": invalidName]))
        )
        #expect(response.status == .badRequest)
      }
    }
  }

  @Test
  func imageUploadRequiresAuthentication() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient()
    )
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let uploadURLResponse = try await client.execute(
        uri: "/images/upload_url",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(uploadURLResponse.status == .unauthorized)

      let imageResponse = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": "cloudflare-image-id"]))
      )
      #expect(imageResponse.status == .unauthorized)
    }
  }

  @Test
  func createImageUploadURL() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient(
        directUpload: .init(
          id: "cloudflare-image-id",
          uploadURL: URL(string: "https://upload.imagedelivery.net/direct-upload")!
        )
      )
    )
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      try await client.execute(
        uri: "/images/upload_url",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        let upload = try JSONDecoder().decode(
          Components.Schemas.CreateImageUploadURLResponse.self,
          from: response.body
        )
        #expect(upload.imageID == "cloudflare-image-id")
        #expect(upload.uploadURL == "https://upload.imagedelivery.net/direct-upload")
      }
    }
  }

  @Test
  func createImageRegistersUploadedImageIdempotently() async throws {
    let arguments = TestArguments()
    let recorder = TestCloudflareImagesCallRecorder()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient(recorder: recorder)
    )
    let ipAddress = UUID().uuidString
    let cloudflareImageID = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      let firstImage = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": cloudflareImageID]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.Image.self, from: response.body)
      }
      #expect(firstImage.imageID == cloudflareImageID)

      let secondImage = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": cloudflareImageID]))
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode(Components.Schemas.Image.self, from: response.body)
      }
      #expect(secondImage.id == firstImage.id)
      #expect(secondImage.imageID == firstImage.imageID)
      #expect(await recorder.verifyUploadedImageCount == 1)
    }
  }

  @Test
  func createImageRejectsCloudflareVerificationFailure() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(
      arguments,
      cloudflareImagesClient: TestCloudflareImagesClient(verifyError: TestCloudflareImagesError())
    )
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      let response = try await client.execute(
        uri: "/images",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["imageID": "missing-image-id"]))
      )
      #expect(response.status == .badRequest)
    }
  }

  @Test
  func createAndGetUsers() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add Users to Database
      let newUsers = try await withThrowingTaskGroup { group in
        for _ in 0..<10 {
          group.addTask {
            let newUser: Components.Schemas.UserToken = try await client.execute(
              uri: "/user",
              method: .post,
              headers: [
                .cfConnectingIP: ipAddress
              ]
            ) { response in
              #expect(response.status == .ok)
              return try JSONDecoder().decode(
                Components.Schemas.UserToken.self,
                from: response.body
              )
            }
            return newUser
          }
        }

        var users: [Components.Schemas.UserToken] = []

        for try await user in group {
          users.append(user)
        }

        return users
      }

      let idsQuery = newUsers.map(\.userID).joined(separator: ",")

      // 2. Get Users from Database and add to Cache
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      ) { response in
        #expect(response.status == .ok)
        let dbUsers = try JSONDecoder().decode([User].self, from: response.body)
        #expect(Set(newUsers.map(\.userID)) == Set(dbUsers.map(\.id.uuidString)))
      }

      // 3. Get Users from Cache
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      ) { response in
        #expect(response.status == .ok)
        let cachedUsers = try JSONDecoder().decode([User].self, from: response.body)
        #expect(Set(newUsers.map(\.userID)) == Set(cachedUsers.map(\.id.uuidString)))
      }
    }
  }

  @Test
  func refreshToken() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self, from: newUserResponse.body)
      // 2. Get User to DB
      let refreshResponse = try await client.execute(
        uri: "/refreshToken",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["refreshToken": newUser.refreshToken])),
      )

      #expect(refreshResponse.status == .ok)
      let getUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: refreshResponse.body
      )
      #expect(newUser.userID == getUser.userID)
    }
  }

  @Test
  func challengeForRegistration() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )
      // 2. Get User to DB
      let challengeResponse = try await client.execute(
        uri: "/challenge",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )

      #expect(challengeResponse.status == .ok)
      let challenge = Data(buffer: challengeResponse.body)
      print(challenge)
    }
  }

  @Test
  func challengeForAuthorization() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let response = try await client.execute(
        uri: "/challenge",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )

      #expect(response.status == .ok)
      let challenge = Data(buffer: response.body)
      print(challenge)
    }
  }

  @Test(.disabled("This test can only be run manually by providing the correct passkey"))
  func addPasskey() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )
      // 2. Get User to DB
      let challengeResponse = try await client.execute(
        uri: "/challenge",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )

      #expect(challengeResponse.status == .ok)
      let challenge = try #require(Data(base64Encoded: String(buffer: challengeResponse.body)))

      let body = Components.Schemas.AddPasskey(
        id: .init(),
        rawId: .init(),
        _type: .init(),
        response: .init(
          clientDataJSON: "",
          attestationObject: "",
        )
      )

      let bodyData = try JSONEncoder().encode(body)

      let addPasskeyResponse = try await client.execute(
        uri: "/passkey?challenge=\(challenge.base64EncodedString())",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ],
        body: ByteBuffer(data: bodyData)
      )

      #expect(addPasskeyResponse.status == .ok)
    }
  }

  @Test
  func sendConfirmEmailAPI() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )

      let response = try await client.execute(
        uri: "/email/verify/start?email=zunda.dev@gmail.com",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(newUser.token)",
        ]
      )

      #expect(response.status == .ok)
    }
  }

  @Test
  func ipAddressRateLimit() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString
    try await app.test(.router) { client in
      for _ in 0..<arguments.rateLimitIPAddressMaxCount! {
        let response = try await client.execute(
          uri: "/.well-known/apple-app-site-association",
          method: .get,
          headers: [
            .cfConnectingIP: ipAddress
          ]
        )
        #expect(response.status == .ok)
      }

      let response = try await client.execute(
        uri: "/.well-known/apple-app-site-association",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(response.status == .tooManyRequests)
    }
  }

  @Test
  func userTokenRateLimit() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )
      let profileResponse = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [
          .authorization: "Bearer \(newUser.token)",
          .cfConnectingIP: ipAddress,
        ],
        body: ByteBuffer(data: JSONEncoder().encode(["name": "Alice"]))
      )
      #expect(profileResponse.status == .ok)
      let createdProfile = try JSONDecoder().decode(
        Components.Schemas.UserProfile.self,
        from: profileResponse.body
      )

      for _ in 0..<(arguments.rateLimitUserTokenMaxCount! - 1) {
        // 2. Get latest user profile
        let getResponse = try await client.execute(
          uri: "/me",
          method: .get,
          headers: [
            .authorization: "Bearer \(newUser.token)",
            .cfConnectingIP: ipAddress,
          ]
        )

        #expect(getResponse.status == .ok)
        let getProfile = try JSONDecoder().decode(
          Components.Schemas.Me.self,
          from: getResponse.body
        )
        #expect(getProfile.userID == newUser.userID)
        #expect(getProfile.userProfile?.name == "Alice")
        #expect(getProfile.userProfile?.createdAt == createdProfile.createdAt)
        #expect(getProfile.emails.isEmpty)
      }

      let getResponse = try await client.execute(
        uri: "/me",
        method: .get,
        headers: [
          .authorization: "Bearer \(newUser.token)",
          .cfConnectingIP: ipAddress,
        ]
      )

      #expect(getResponse.status == .tooManyRequests)
    }
  }

  @Test
  func ipAddressRateLimitPerEndpoint() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      for _ in 0..<30 {
        let newUserResponse = try await client.execute(
          uri: "/user",
          method: .post,
          headers: [
            .cfConnectingIP: ipAddress
          ]
        )
        #expect(newUserResponse.status == .ok)
      }

      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress
        ]
      )
      #expect(newUserResponse.status == .internalServerError)
    }
  }
}

private struct TestCloudflareImagesClient: CloudflareImagesClientProtocol {
  var directUpload: CloudflareDirectUpload = .init(
    id: "cloudflare-image-id",
    uploadURL: URL(string: "https://upload.imagedelivery.net/direct-upload")!
  )
  var directUploadError: TestCloudflareImagesError?
  var verifyError: TestCloudflareImagesError?
  var imageURLError: TestCloudflareImagesError?
  var recorder: TestCloudflareImagesCallRecorder?

  func createDirectUploadURL(userID: UUID) async throws -> CloudflareDirectUpload {
    await recorder?.recordCreateDirectUploadURL()
    if let directUploadError {
      throw directUploadError
    }
    return directUpload
  }

  func verifyUploadedImage(id: String, userID: UUID) async throws {
    await recorder?.recordVerifyUploadedImage()
    if let verifyError {
      throw verifyError
    }
  }

  func imageURL(id: String, userID: UUID) async throws -> URL {
    await recorder?.recordImageURL()
    if let imageURLError {
      throw imageURLError
    }
    return URL(string: "https://imagedelivery.net/account-hash/\(id)/public")!
  }
}

private actor TestCloudflareImagesCallRecorder {
  private(set) var createDirectUploadURLCount = 0
  private(set) var verifyUploadedImageCount = 0
  private(set) var imageURLCount = 0

  func recordCreateDirectUploadURL() {
    createDirectUploadURLCount += 1
  }

  func recordVerifyUploadedImage() {
    verifyUploadedImageCount += 1
  }

  func recordImageURL() {
    imageURLCount += 1
  }
}

private struct TestCloudflareImagesError: Error {}
