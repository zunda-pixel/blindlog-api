import Foundation
import WebAuthn

struct WebAuthnRegistrationResult: Sendable {
  var publicKey: [UInt8]
  var signCount: UInt32
}

struct WebAuthnAuthenticationResult: Sendable {
  var credentialID: String
  var newSignCount: UInt32
}

protocol WebAuthnProtocol: Sendable {
  func beginRegistration(
    user: PublicKeyCredentialUserEntity,
    timeout: Duration?,
    attestation: AttestationConveyancePreference,
    publicKeyCredentialParameters: [PublicKeyCredentialParameters]
  ) -> PublicKeyCredentialCreationOptions

  func finishRegistration(
    challenge: [UInt8],
    credentialCreationData: RegistrationCredential,
    requireUserVerification: Bool,
    supportedPublicKeyAlgorithms: [PublicKeyCredentialParameters],
    pemRootCertificatesByFormat: [AttestationFormat: [Data]],
    confirmCredentialIDNotRegisteredYet: @Sendable @concurrent (String) async throws -> Bool
  ) async throws -> WebAuthnRegistrationResult

  func beginAuthentication(
    timeout: Duration?,
    allowCredentials: [PublicKeyCredentialDescriptor]?,
    userVerification: UserVerificationRequirement
  ) -> PublicKeyCredentialRequestOptions

  func finishAuthentication(
    credential: AuthenticationCredential,
    expectedChallenge: [UInt8],
    credentialPublicKey: [UInt8],
    credentialCurrentSignCount: UInt32,
    requireUserVerification: Bool
  ) throws -> WebAuthnAuthenticationResult
}

struct LiveWebAuthn: WebAuthnProtocol {
  var manager: WebAuthnManager

  func beginRegistration(
    user: PublicKeyCredentialUserEntity,
    timeout: Duration?,
    attestation: AttestationConveyancePreference,
    publicKeyCredentialParameters: [PublicKeyCredentialParameters]
  ) -> PublicKeyCredentialCreationOptions {
    manager.beginRegistration(
      user: user,
      timeout: timeout,
      attestation: attestation,
      publicKeyCredentialParameters: publicKeyCredentialParameters
    )
  }

  func finishRegistration(
    challenge: [UInt8],
    credentialCreationData: RegistrationCredential,
    requireUserVerification: Bool,
    supportedPublicKeyAlgorithms: [PublicKeyCredentialParameters],
    pemRootCertificatesByFormat: [AttestationFormat: [Data]],
    confirmCredentialIDNotRegisteredYet: @Sendable @concurrent (String) async throws -> Bool
  ) async throws -> WebAuthnRegistrationResult {
    let credential = try await manager.finishRegistration(
      challenge: challenge,
      credentialCreationData: credentialCreationData,
      requireUserVerification: requireUserVerification,
      supportedPublicKeyAlgorithms: supportedPublicKeyAlgorithms,
      pemRootCertificatesByFormat: pemRootCertificatesByFormat,
      confirmCredentialIDNotRegisteredYet: confirmCredentialIDNotRegisteredYet
    )
    return WebAuthnRegistrationResult(
      publicKey: credential.publicKey,
      signCount: credential.signCount
    )
  }

  func beginAuthentication(
    timeout: Duration?,
    allowCredentials: [PublicKeyCredentialDescriptor]?,
    userVerification: UserVerificationRequirement
  ) -> PublicKeyCredentialRequestOptions {
    manager.beginAuthentication(
      timeout: timeout,
      allowCredentials: allowCredentials,
      userVerification: userVerification
    )
  }

  func finishAuthentication(
    credential: AuthenticationCredential,
    expectedChallenge: [UInt8],
    credentialPublicKey: [UInt8],
    credentialCurrentSignCount: UInt32,
    requireUserVerification: Bool
  ) throws -> WebAuthnAuthenticationResult {
    let verifiedAuthentication = try manager.finishAuthentication(
      credential: credential,
      expectedChallenge: expectedChallenge,
      credentialPublicKey: credentialPublicKey,
      credentialCurrentSignCount: credentialCurrentSignCount,
      requireUserVerification: requireUserVerification
    )
    return WebAuthnAuthenticationResult(
      credentialID: verifiedAuthentication.credentialID.asString(),
      newSignCount: verifiedAuthentication.newSignCount
    )
  }
}
