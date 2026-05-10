import Foundation
import Records

@Table("images")
struct ImageRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("user_id") var userID: UUID
  @Column("cloudflare_image_id") var cloudflareImageID: String
  @Column("created_at") var createdAt: Date
}
