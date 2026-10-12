class_name UnitInfoPanel
extends VBoxContainer
## Presentation-only selected-unit surface. Gameplay remains behind board callbacks.

const GROUP_ATTACKS:="attacks"
const GROUP_STANCES:="stances"
const GROUP_SPECIAL:="special"
const GROUP_CITY:="city"

var title_label: Label
var subtitle_label: Label
var icon_rect: TextureRect
var preview: ModelPreview
var health_bar: ProgressBar
var health_label: Label
var health_icon: TextureRect
var health_row: HBoxContainer
var squad_label: Label
var squad_icon: TextureRect
var squad_row: HBoxContainer
var stats_grid: GridContainer
var queued_panel: PanelContainer
var queued_label: Label
var status_heading: Label
var status_flow: HFlowContainer
var details_label: Label
var details_button: Button
var _entity_id: int=-1
var _details_open: bool=false
var action_sections: Dictionary={}
var action_flows: Dictionary={}

func _ready() -> void:
	name="UnitInfoPanel"; mouse_filter=Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation",7)
	var header:=HBoxContainer.new(); header.add_theme_constant_override("separation",8); add_child(header)
	title_label=_label(22,header); title_label.name="UnitName"; title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	icon_rect=TextureRect.new(); icon_rect.name="UnitIcon"; icon_rect.custom_minimum_size=Vector2(28,28); icon_rect.expand_mode=TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL; icon_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE; header.add_child(icon_rect)
	subtitle_label=_label(13); subtitle_label.name="UnitRole"; subtitle_label.modulate=Color("#adc1cb")
	subtitle_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var summary:=HBoxContainer.new(); summary.add_theme_constant_override("separation",10); add_child(summary)
	preview=ModelPreview.new(); preview.name="UnitPreviewViewport"; preview.custom_minimum_size=Vector2(128,112); summary.add_child(preview)
	var vital:=VBoxContainer.new(); vital.size_flags_horizontal=Control.SIZE_EXPAND_FILL; vital.add_theme_constant_override("separation",4); summary.add_child(vital)
	health_row=HBoxContainer.new(); vital.add_child(health_row)
	health_icon=StatIcons.control("health","Health"); health_row.add_child(health_icon)
	health_label=_label(15,health_row); health_label.name="HealthValue"; health_label.mouse_filter=Control.MOUSE_FILTER_STOP
	health_bar=ProgressBar.new(); health_bar.name="HealthBar"; health_bar.show_percentage=false; health_bar.custom_minimum_size=Vector2(108,10); health_bar.mouse_filter=Control.MOUSE_FILTER_STOP; vital.add_child(health_bar)
	var fill:=StyleBoxFlat.new(); fill.bg_color=Color("#79d36f"); fill.corner_radius_top_left=3; fill.corner_radius_top_right=3; fill.corner_radius_bottom_left=3; fill.corner_radius_bottom_right=3
	health_bar.add_theme_stylebox_override("fill",fill)
	squad_row=HBoxContainer.new(); vital.add_child(squad_row)
	squad_icon=StatIcons.control("group","Group size"); squad_row.add_child(squad_icon)
	squad_label=_label(13,squad_row); squad_label.name="SquadCount"; squad_label.mouse_filter=Control.MOUSE_FILTER_STOP
	stats_grid=GridContainer.new(); stats_grid.name="EffectiveStats"; stats_grid.columns=2; stats_grid.add_theme_constant_override("h_separation",14); stats_grid.add_theme_constant_override("v_separation",2); vital.add_child(stats_grid)
	queued_panel=PanelContainer.new(); queued_panel.name="QueuedCombat"; queued_panel.visible=false; add_child(queued_panel)
	var queued_style:=StyleBoxFlat.new(); queued_style.bg_color=Color(0.38,0.08,0.08,0.92); queued_style.corner_radius_top_left=4; queued_style.corner_radius_top_right=4; queued_style.corner_radius_bottom_left=4; queued_style.corner_radius_bottom_right=4; queued_style.content_margin_left=8; queued_style.content_margin_right=8; queued_style.content_margin_top=5; queued_style.content_margin_bottom=5
	queued_panel.add_theme_stylebox_override("panel",queued_style); queued_label=_label(13,queued_panel); queued_label.name="QueuedCombatLabel"
	queued_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for record: Dictionary in [{"id":GROUP_ATTACKS,"label":"ATTACKS"},{"id":GROUP_STANCES,"label":"COMBAT STANCE"},{"id":GROUP_SPECIAL,"label":"SPECIAL ACTIONS"},{"id":GROUP_CITY,"label":"SPIDER CITY"}]: _create_action_section(record.id,record.label)
	status_heading=_heading("STATUS"); status_heading.visible=false
	status_flow=HFlowContainer.new(); status_flow.name="StatusBadges"; status_flow.visible=false; status_flow.add_theme_constant_override("h_separation",5); status_flow.add_theme_constant_override("v_separation",4); add_child(status_flow)
	details_button=Button.new(); details_button.text="Details"; details_button.toggle_mode=true; details_button.focus_mode=Control.FOCUS_NONE
	details_button.toggled.connect(func(open: bool) -> void: _details_open=open; details_label.visible=open)
	add_child(details_button)
	details_label=_label(12); details_label.name="UnitDetails"; details_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; details_label.visible=false
	visible=false

func show_unit(title: String,subtitle: String,visual_id: String,hp: int,max_hp: int,squad_current: int=0,squad_max: int=0,icon_path: String="",entity_id: int=-1) -> void:
	if entity_id!=_entity_id: _details_open=false; _entity_id=entity_id
	details_button.visible=true; details_button.set_pressed_no_signal(_details_open); details_label.visible=_details_open
	visible=true; preview.visible=true; health_row.visible=true; health_bar.visible=true; health_label.visible=true; title_label.text=title.to_upper(); subtitle_label.text=subtitle
	icon_rect.texture=load(icon_path) as Texture2D if not icon_path.is_empty() and ResourceLoader.exists(icon_path) else null; icon_rect.visible=icon_rect.texture!=null
	health_bar.max_value=maxi(1,max_hp); health_bar.value=clampi(hp,0,max_hp)
	health_label.text="%d / %d" % [hp,max_hp]
	health_icon.tooltip_text="Health: %d / %d" % [hp,max_hp]; health_label.tooltip_text=health_icon.tooltip_text; health_bar.tooltip_text=health_icon.tooltip_text
	var ratio:=float(hp)/maxf(1.0,float(max_hp)); health_bar.modulate=Color("#e66b61") if ratio<=0.3 else (Color("#e9c46a") if ratio<=0.6 else Color.WHITE)
	squad_row.visible=squad_max>1; squad_label.visible=squad_row.visible; squad_label.text="%d / %d" % [squad_current,squad_max]
	squad_icon.tooltip_text="Group size: %d / %d living members" % [squad_current,squad_max]; squad_label.tooltip_text=squad_icon.tooltip_text
	preview.show_model(visual_id)

func show_context(title: String,subtitle: String,visual_id: String="",hp: int=-1,max_hp: int=-1) -> void:
	visible=true; title_label.text=title.to_upper(); subtitle_label.text=subtitle
	details_button.visible=false; details_label.visible=true; _entity_id=-1; _details_open=false
	icon_rect.visible=false; icon_rect.texture=null
	preview.visible=not visual_id.is_empty()
	if visual_id.is_empty(): preview.clear_model()
	else: preview.show_model(visual_id)
	health_label.visible=hp>=0 and max_hp>0; health_row.visible=health_label.visible; health_bar.visible=health_label.visible; squad_row.visible=false; squad_label.visible=false
	if health_label.visible:
		health_label.text="%d / %d" % [hp,max_hp]; health_bar.max_value=max_hp; health_bar.value=hp; health_bar.modulate=Color.WHITE
		health_icon.tooltip_text="Health: %d / %d" % [hp,max_hp]; health_label.tooltip_text=health_icon.tooltip_text; health_bar.tooltip_text=health_icon.tooltip_text
	set_stats([]); set_statuses([]); set_queued(""); clear_actions()

func hide_panel() -> void:
	visible=false; preview.clear_model(); clear_actions(); set_statuses([]); set_queued("")

func set_stats(stats: Array[Dictionary]) -> void:
	_clear_children(stats_grid)
	for stat: Dictionary in stats:
		var tip:=String(stat.get("tooltip",""))
		var key:=StatIcons.control(String(stat.get("icon",String(stat.get("label","")).to_lower())),tip); stats_grid.add_child(key)
		var value:=_label(14,stats_grid); value.text=String(stat.get("value","—")); value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; value.mouse_filter=Control.MOUSE_FILTER_STOP; value.tooltip_text=tip

func set_queued(text: String) -> void:
	queued_panel.visible=not text.is_empty(); queued_label.text=text

func set_statuses(statuses: Array[Dictionary]) -> void:
	_clear_children(status_flow)
	status_heading.visible=not statuses.is_empty(); status_flow.visible=not statuses.is_empty()
	for status: Dictionary in statuses:
		var badge:=Label.new(); badge.add_theme_font_size_override("font_size",11); badge.text="  %s  " % String(status.get("label","")); badge.tooltip_text=String(status.get("tooltip","")); badge.mouse_filter=Control.MOUSE_FILTER_STOP
		var style:=StyleBoxFlat.new(); style.bg_color=Color(status.get("color","#344852")); style.corner_radius_top_left=7; style.corner_radius_top_right=7; style.corner_radius_bottom_left=7; style.corner_radius_bottom_right=7
		badge.add_theme_stylebox_override("normal",style); status_flow.add_child(badge)

func clear_actions() -> void:
	for group: String in action_flows:
		_clear_children(action_flows[group]); action_sections[group].visible=false

func add_action(group: String,label: String,callback: Callable,tooltip: String="",disabled_reason: String="",selected: bool=false) -> Button:
	if not action_flows.has(group): group=GROUP_SPECIAL
	var button:=Button.new(); button.text=label; button.focus_mode=Control.FOCUS_NONE; button.add_theme_font_size_override("font_size",13)
	button.toggle_mode=group in [GROUP_ATTACKS,GROUP_STANCES] and not label.begins_with("Cancel"); button.set_pressed_no_signal(selected)
	button.clip_text=group==GROUP_CITY
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS if group==GROUP_CITY else TextServer.OVERRUN_NO_TRIMMING
	if group==GROUP_CITY: button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.disabled=not disabled_reason.is_empty(); button.tooltip_text=label+("\n"+tooltip if not tooltip.is_empty() else "")+(("\n\nUnavailable: "+disabled_reason) if not disabled_reason.is_empty() else "")
	if callback.is_valid(): button.pressed.connect(callback)
	action_flows[group].add_child(button); action_sections[group].visible=true
	return button

func add_action_note(group: String,text: String) -> void:
	var label:=_label(12,action_flows[group]); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_sections[group].visible=true

func add_action_value(group: String,icon_id: String,label: String,value: String,tooltip: String) -> void:
	var row:=HBoxContainer.new(); action_flows[group].add_child(row)
	row.add_child(StatIcons.control(icon_id,tooltip))
	var text:=_label(12,row); text.text=label+"  "+value; text.tooltip_text=tooltip; text.mouse_filter=Control.MOUSE_FILTER_STOP; text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action_sections[group].visible=true

func _create_action_section(id: String,label: String) -> void:
	var section:=VBoxContainer.new(); section.name=id.capitalize()+"Section"; section.visible=false; section.add_theme_constant_override("separation",3); add_child(section)
	var heading:=_heading(label,section)
	var flow: Container=VBoxContainer.new() if id==GROUP_CITY else HFlowContainer.new()
	flow.name=id.capitalize()+"Actions"; flow.add_theme_constant_override("h_separation",5); flow.add_theme_constant_override("v_separation",4); section.add_child(flow)
	action_sections[id]=section; action_flows[id]=flow

func _heading(text: String,parent: Control=self) -> Label:
	var label:=_label(12,parent); label.text=text; label.modulate=Color("#7fb7c9"); return label

func _label(size: int=13,parent: Control=self) -> Label:
	var label:=Label.new(); label.add_theme_font_size_override("font_size",size); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(label); return label

func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children(): parent.remove_child(child); child.queue_free()
