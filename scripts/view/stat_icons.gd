class_name StatIcons
extends RefCounted
## Shared vector vocabulary for compact values and accessible hover labels.
const IDS: Array[String]=["health","group","armour","damage","movement","range","vision","detection","slots","lifetime"]
static var _textures: Dictionary[String,Texture2D]={}
static func texture(id: String) -> Texture2D:
	if id not in IDS: return null
	if not _textures.has(id): _textures[id]=load("res://assets/ui/stats/%s.svg" % id) as Texture2D
	return _textures[id]

static func control(id: String,tooltip: String) -> TextureRect:
	var icon:=TextureRect.new(); icon.name=id.capitalize()+"Icon"
	icon.texture=texture(id); icon.custom_minimum_size=Vector2(20,20)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_STOP; icon.tooltip_text=tooltip
	return icon
