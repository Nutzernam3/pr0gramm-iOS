
import Foundation

struct Tags: Codable {
	let id: Int
	let confidence: Double
	let tag: String

	enum CodingKeys: String, CodingKey {
		case id = "id"
		case confidence = "confidence"
		case tag = "tag"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(Int.self, forKey: .id)
		confidence = try values.decode(Double.self, forKey: .confidence)
		tag = try values.decode(String.self, forKey: .tag)
	}
}
