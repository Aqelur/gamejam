class_name AdvisorData
extends Resource

## Danışman kart verisine dokunmaz; damga basılınca kartın etkisini değiştirir.
## Kurallar scenarios/cards.md içindeki Danışmanlar bölümündedir.

const MYTH_CARDS: Array[String] = ["fool_doorway", "fool_goat"]

@export var id: String = ""
@export var display_name: String = ""
@export var portrait: Texture2D
@export_multiline var says: String = ""
@export_multiline var effects_text: String = ""
@export var price := 15


func modify(card: CardData, approved: bool, effect: Vector4i) -> Vector4i:
	match id:
		"sengor":
			if approved and card.id in MYTH_CARDS:
				return Vector4i.ZERO
			if approved and effect.x > 0:
				if card.character_name == "Chief Seismologist":
					effect.x += 5
				elif card.character_name == "The Influencer":
					effect.x -= 5
		"gorur":
			if card.character_name == "The Contractor":
				if approved and effect.z < 0:
					effect.z += 5
			elif card.character_name == "Minister of Urban Planning":
				if not approved:
					effect.x -= 5
				elif effect.y < 0:
					effect.y += 5
		"usumezsoy":
			if approved and card.character_name == "Chief Seismologist" and effect.x > 0:
				effect.x -= 5
	return effect


func card_note(card: CardData) -> String:
	if id == "sengor" and card.id in MYTH_CARDS:
		return "%s: \"MYTH. Approving it does nothing.\"" % display_name
	return ""
