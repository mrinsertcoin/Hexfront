class_name StrategicNotificationFeed
extends PanelContainer
## Bounded, ephemeral match messages. Focus targets are logical IDs/cells only.

signal focus_requested(cell_id: int,entity_id: int)

enum Severity { INFO, SUCCESS, WARNING, CRITICAL }
const COLORS: Array[Color]=[Color("#c7d2d8"),Color("#9cdb8e"),Color("#f2cc76"),Color("#ff7b72")]
const NAMES: Array[String]=["INFO","SUCCESS","WARNING","CRITICAL"]
const MAX_ITEMS:=6

var records: Array[Dictionary]=[]
var list: VBoxContainer

func _ready() -> void:
	MythicFrame.apply(self,true)
	visible=false
	mouse_filter=Control.MOUSE_FILTER_STOP
	var margin:=MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,8)
	add_child(margin)
	list=VBoxContainer.new(); list.add_theme_constant_override("separation",3); margin.add_child(list)

func post(message: String,severity: int=Severity.INFO,cell_id: int=-1,entity_id: int=-1) -> void:
	visible=true
	records.push_front({"message":message,"severity":clampi(severity,0,Severity.size()-1),"cell_id":cell_id,"entity_id":entity_id})
	if records.size()>MAX_ITEMS: records.resize(MAX_ITEMS)
	_rebuild()

func clear_all() -> void:
	records.clear(); _rebuild(); visible=false

func _rebuild() -> void:
	if list==null: return
	for child: Node in list.get_children():
		list.remove_child(child); child.queue_free()
	for record: Dictionary in records:
		var button:=Button.new()
		button.flat=true; button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.focus_mode=Control.FOCUS_NONE
		button.text="[%s] %s" % [NAMES[record.severity],record.message]
		button.add_theme_color_override("font_color",COLORS[record.severity])
		button.disabled=int(record.cell_id)<0 and int(record.entity_id)<0
		button.tooltip_text="Focus this event on the world." if not button.disabled else ""
		button.pressed.connect(_focus.bind(int(record.cell_id),int(record.entity_id)))
		list.add_child(button)

func _focus(cell_id: int,entity_id: int) -> void:
	focus_requested.emit(cell_id,entity_id)
