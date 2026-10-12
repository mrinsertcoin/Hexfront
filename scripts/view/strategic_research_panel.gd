class_name StrategicResearchPanel
extends PanelContainer
## Definition-driven research browser. It emits intent and never mutates game state.

signal research_requested(technology_id: String)
signal close_requested

const LOCKED:="LOCKED"
const AVAILABLE:="AVAILABLE"
const RESEARCHING:="RESEARCHING"
const COMPLETED:="COMPLETED"

var registry: ContentRegistry
var rules: GameRules
var controller_id: int
var title_label: Label
var progress_label: Label
var tree: VBoxContainer
var detail_label: Label
var start_button: Button
var selected_id: String=""
var zoom_level: float=1.0
var graph: LivingResearchTree
var scroll: ScrollContainer
var detail_title: Label
var legend: Label
var progress_meter: ProgressBar

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	var panel_style:=StyleBoxFlat.new()
	panel_style.bg_color=Color("#111c22")
	panel_style.border_color=Color("#54727c")
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left=8; panel_style.corner_radius_top_right=8
	panel_style.corner_radius_bottom_left=8; panel_style.corner_radius_bottom_right=8
	add_theme_stylebox_override("panel",panel_style)
	MythicFrame.apply(self)
	var margin:=MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",8); margin.add_child(column)
	var header:=HBoxContainer.new(); column.add_child(header)
	title_label=Label.new(); title_label.text="Research"; title_label.add_theme_font_size_override("font_size",22); title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title_label)
	title_label.clip_text=true; title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var close:=Button.new(); close.text="Close"; close.focus_mode=Control.FOCUS_NONE; close.pressed.connect(func(): close_requested.emit()); header.add_child(close)
	var zoom_out:=Button.new(); zoom_out.name="ZoomOut"; zoom_out.text="−"; zoom_out.tooltip_text="Zoom research tree out"; zoom_out.focus_mode=Control.FOCUS_NONE; zoom_out.pressed.connect(_zoom.bind(-0.1)); header.add_child(zoom_out)
	var zoom_in:=Button.new(); zoom_in.name="ZoomIn"; zoom_in.text="+"; zoom_in.tooltip_text="Zoom research tree in"; zoom_in.focus_mode=Control.FOCUS_NONE; zoom_in.pressed.connect(_zoom.bind(0.1)); header.add_child(zoom_in)
	progress_label=Label.new(); progress_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; progress_label.custom_minimum_size.x=300; column.add_child(progress_label)
	progress_meter=ProgressBar.new(); progress_meter.show_percentage=false; progress_meter.custom_minimum_size.y=6; column.add_child(progress_meter)
	var growth_style:=StyleBoxFlat.new(); growth_style.bg_color=Color("a8bd79"); growth_style.set_corner_radius_all(3); progress_meter.add_theme_stylebox_override("fill",growth_style)
	legend=Label.new(); legend.custom_minimum_size.x=300; legend.size.x=300
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	legend.text="Select a root to inspect · Research grows from completed roots · Scroll to explore · − / + zoom"; column.add_child(legend)
	scroll=ScrollContainer.new(); scroll.follow_focus=true; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; column.add_child(scroll)
	tree=VBoxContainer.new(); tree.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tree.add_theme_constant_override("separation",6); scroll.add_child(tree)
	detail_title=Label.new(); detail_title.add_theme_font_size_override("font_size",19); column.add_child(detail_title)
	detail_label=Label.new(); detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; detail_label.custom_minimum_size=Vector2(300,86); column.add_child(detail_label)
	start_button=Button.new(); start_button.text="Start Research"; start_button.focus_mode=Control.FOCUS_NONE; start_button.pressed.connect(_start_selected); column.add_child(start_button)

func configure(game_rules: GameRules,actor: int) -> void:
	rules=game_rules; registry=rules.state.registry; controller_id=actor
	refresh()
	_center_selected.call_deferred()

func _center_selected() -> void:
	if graph==null or not graph.node_buttons.has(selected_id): return
	var button: Button=graph.node_buttons[selected_id]
	scroll.scroll_horizontal=maxi(0,roundi(button.position.x+button.size.x*0.5-scroll.size.x*0.5))
	scroll.scroll_vertical=maxi(0,roundi(button.position.y-32))

func technology_state(id: String) -> String:
	var player:=rules.state.player_for_controller(controller_id)
	if player==null: return LOCKED
	if player.research.is_completed(id): return COMPLETED
	if player.research.current_technology_id==id: return RESEARCHING
	if player.research.is_available(id,registry,registry.faction(player.faction_id).technology_ids): return AVAILABLE
	return LOCKED

func locked_reason(id: String) -> String:
	var definition:=registry.technology(id)
	var missing:=PackedStringArray()
	var player:=rules.state.player_for_controller(controller_id)
	for prerequisite: String in definition.prerequisite_ids:
		if player==null or not player.research.is_completed(prerequisite): missing.append(registry.technology(prerequisite).display_name)
	if not missing.is_empty(): return "Requires: "+", ".join(missing)
	return rules.research_rules.can_start_research(controller_id,id)

func refresh() -> void:
	if tree==null or rules==null: return
	for child: Node in tree.get_children():
		child.visible=false; tree.remove_child(child); child.queue_free()
	var player:=rules.state.player_for_controller(controller_id)
	if player==null: return
	var faction:=registry.faction(player.faction_id)
	var living:=faction.id=="living_migration"
	graph=null
	title_label.text="The Living Migration · Root of Knowledge" if living else faction.display_name+" Research"
	title_label.tooltip_text=title_label.text
	var font: Font=MythicFrame.TITLE_FONT
	title_label.add_theme_font_override("font",font); detail_title.add_theme_font_override("font",font)
	title_label.add_theme_font_size_override("font_size",20 if living else 22)
	legend.visible=living
	var style:=get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color=Color("101c15") if living else Color("111c22")
	style.border_color=Color("71865b") if living else Color("54727c")
	if selected_id.is_empty() or selected_id not in faction.technology_ids:
		selected_id=faction.technology_ids[0] if not faction.technology_ids.is_empty() else ""
	if player.research.current_technology_id.is_empty(): progress_label.text="No active research"
	else:
		var current:=registry.technology(player.research.current_technology_id)
		progress_label.text="Active: %s — %d / %d" % [current.display_name,player.research.accumulated_progress,current.research_cost]
	progress_meter.visible=not player.research.current_technology_id.is_empty()
	if progress_meter.visible:
		progress_meter.max_value=maxi(1,registry.technology(player.research.current_technology_id).research_cost)
		progress_meter.value=player.research.accumulated_progress
	if living:
		var organs:=0
		for unit: GameState.Unit in rules.state.units.values():
			if unit.controller_id==controller_id and unit.spider_state!=null: organs+=unit.spider_state.building_count("research_building")
		var config:=rules.living_migration_rules.config_for(controller_id)
		var rate:=config.research_per_building+(config.improved_research_building_bonus if rules.research_rules.has_unlock_tag(controller_id,"root_memory") else 0)
		progress_label.text+=" · %d RP / round" % (organs*rate) if organs>0 else " · Build a Research organ inside a Living Spider to gain research."
	if living:
		graph=LivingResearchTree.new(); tree.add_child(graph)
		graph.technology_selected.connect(_select); graph.rebuild(self,faction.technology_ids,zoom_level)
	for id: String in faction.technology_ids if not living else PackedStringArray():
		var definition:=registry.technology(id)
		if definition==null: continue
		var row:=Button.new(); row.focus_mode=Control.FOCUS_NONE; row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		var state_name:=technology_state(id)
		var dependency:=PackedStringArray()
		for prerequisite: String in definition.prerequisite_ids: dependency.append(registry.technology(prerequisite).display_name)
		row.text="[%s] %s  (%d)" % [state_name,definition.display_name,definition.research_cost]
		if not dependency.is_empty(): row.text+="\n  ↳ Requires: "+", ".join(dependency)
		row.tooltip_text=StrategicTooltip.technology(definition,registry)
		row.add_theme_font_size_override("font_size",roundi(15.0*zoom_level))
		ContentIcon.apply(row,definition)
		row.pressed.connect(_select.bind(id)); tree.add_child(row)
	_update_detail()
	queue_redraw()

func _select(id: String) -> void:
	selected_id=id; _update_detail()
	if graph!=null: graph.update_selection()

func _update_detail() -> void:
	if selected_id.is_empty(): detail_title.text=""; detail_label.text="No technologies authored for this faction."; start_button.disabled=true; return
	var definition:=registry.technology(selected_id)
	detail_title.text=definition.display_name.replace(" (Provisional)","")
	var reason:=rules.research_rules.can_start_research(controller_id,selected_id)
	if technology_state(selected_id)==LOCKED: reason=locked_reason(selected_id)
	detail_label.text=StrategicTooltip.technology(definition,registry)
	if graph!=null: detail_label.text=detail_label.text.substr(detail_label.text.find("\n")+1)
	if not reason.is_empty(): detail_label.text+="\n\n"+reason
	start_button.disabled=not reason.is_empty()
	start_button.tooltip_text=reason

func _start_selected() -> void:
	if not selected_id.is_empty() and rules.research_rules.can_start_research(controller_id,selected_id).is_empty(): research_requested.emit(selected_id)

func _zoom(amount: float) -> void:
	zoom_level=clampf(zoom_level+amount,0.65,1.4); refresh(); _center_selected.call_deferred()
