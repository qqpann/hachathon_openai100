extends RefCounted
## Packaged games include Japanese glyphs even on systems without Japanese fonts.
static func make(names: PackedStringArray, weight: int = 600) -> Font:
	if not OS.has_feature("editor"):
		var face = FontVariation.new()
		face.base_font = preload("res://assets/fonts/NotoSansCJKjp-Regular.otf")
		face.variation_embolden = 0.7 if weight < 700 else 1.1
		return face
	var face = SystemFont.new()
	face.font_names = names
	face.font_weight = weight
	return face
