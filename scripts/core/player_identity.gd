class_name PlayerIdentity
extends RefCounted
## Shared, faction-independent ownership presentation for the four FFA slots.

const COLOR_HEX: PackedStringArray = ["#45b7e8", "#f29e38", "#58c77a", "#ad7bea"]
const COLOR_NAMES: PackedStringArray = ["Cyan", "Orange", "Green", "Violet"]

static func color_hex_for_slot(slot_index: int) -> String:
	return COLOR_HEX[posmod(slot_index, COLOR_HEX.size())]

static func color_name_for_slot(slot_index: int) -> String:
	return COLOR_NAMES[posmod(slot_index, COLOR_NAMES.size())]

static func color_for_hex(value: String) -> Color:
	return Color(value if value.is_valid_html_color() else "#9ca3a5")
