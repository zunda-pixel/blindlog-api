import Foundation
import NIOCore
import Valkey
import ValkeyVapor
import Vapor

func routes(_ app: Application) throws {
  try app.register(collection: UserController())
}
