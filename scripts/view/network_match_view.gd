class_name NetworkMatchView
extends Control
## Development client presentation backed only by permitted network snapshots.

signal leave_requested

var session: NetworkSession
var connection_label: Label
var turn_label: Label
var resources_label: Label
var entities_label: RichTextLabel
var command_type: OptionButton
var parameters_edit: LineEdit
var feedback_label: Label
var revision_label: Label
var players_label: RichTextLabel
var send_button: Button
var end_turn_button: Button

func configure(value: NetworkSession) -> void: session=value

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new(); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color=Color("#101923"); add_child(background)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	background.add_child(margin)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",10); margin.add_child(column)
	var heading:=Label.new(); heading.text="HEXFRONT — Network Match"; heading.add_theme_font_size_override("font_size",28); column.add_child(heading)
	connection_label=Label.new(); turn_label=Label.new(); revision_label=Label.new(); resources_label=Label.new()
	column.add_child(connection_label); column.add_child(turn_label); column.add_child(revision_label); column.add_child(resources_label)
	players_label=RichTextLabel.new(); players_label.bbcode_enabled=true; players_label.fit_content=true; players_label.custom_minimum_size.y=90; column.add_child(players_label)
	entities_label=RichTextLabel.new(); entities_label.bbcode_enabled=true; entities_label.fit_content=false
	entities_label.size_flags_vertical=Control.SIZE_EXPAND_FILL; entities_label.custom_minimum_size.y=260; column.add_child(entities_label)
	var help:=Label.new(); help.text="Development command interface — parameters are a JSON object using stable entity/content IDs."
	help.modulate=Color("#a8bac8"); column.add_child(help)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",8); column.add_child(row)
	command_type=OptionButton.new(); command_type.custom_minimum_size.x=250
	for type: String in CommandDispatcher.COMMAND_TYPES: command_type.add_item(type)
	row.add_child(command_type)
	parameters_edit=LineEdit.new(); parameters_edit.placeholder_text='{"unit_id": 1, "destination": 42}'
	parameters_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(parameters_edit)
	send_button=Button.new(); send_button.text="Send Command"; send_button.pressed.connect(_send_command); row.add_child(send_button)
	end_turn_button=Button.new(); end_turn_button.text="End Turn"; end_turn_button.pressed.connect(func()->void: session.submit_command(CommandDispatcher.END_TURN,{})); row.add_child(end_turn_button)
	feedback_label=Label.new(); feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(feedback_label)
	var leave:=Button.new(); leave.text="Leave Match"; leave.pressed.connect(func()->void: leave_requested.emit()); column.add_child(leave)
	if session==null:
		feedback_label.text="Network session unavailable."; return
	session.observation_received.connect(_show_observation)
	session.command_completed.connect(_show_result)
	session.status_changed.connect(_show_status)
	_show_status(session.status,session.status_message)
	if not session.latest_observation.is_empty(): _show_observation(session.latest_observation)

func _send_command() -> void:
	var text:=parameters_edit.text.strip_edges()
	var parameters: Dictionary={}
	if not text.is_empty():
		var parsed: Variant=JSON.parse_string(text)
		if not parsed is Dictionary:
			feedback_label.text="Parameters must be a JSON object."; return
		parameters=parsed
	var type:=command_type.get_item_text(command_type.selected)
	if session.submit_command(type,parameters)<0: feedback_label.text="The session is not ready for commands."

func _show_status(_status: int,message: String) -> void:
	connection_label.text="Local player: P%d (%s) | Connection: %s" % [session.local_player_id,session.local_player_name,message]

func _show_result(result: Dictionary) -> void:
	feedback_label.text=("Accepted: " if bool(result.get("accepted",false)) else "Rejected: ")+String(result.get("public_reason",""))

func _show_observation(snapshot: Dictionary) -> void:
	var turn: Dictionary=snapshot.get("turn",{})
	var winner_id:=int(turn.get("winner_id",0))
	turn_label.text="Active player: P%d | Round %d%s%s" % [int(turn.get("active_player",0)),int(turn.get("round_number",0)),
		" | Neutral phase" if bool(turn.get("neutral_phase",false)) else ""," | Match complete" if winner_id!=0 else ""]
	var player_lines:=PackedStringArray(["[b]PLAYERS[/b]"])
	for player: Dictionary in snapshot.get("players",[]):
		var marker:="WINNER" if int(player.player_id)==winner_id else ("ELIMINATED" if bool(player.get("defeated",false)) else ("ACTIVE" if int(player.player_id)==int(turn.get("active_player",0)) else "ALIVE"))
		if not bool(player.get("connected",true)): marker+=" / DISCONNECTED"
		player_lines.append("[color=%s]●[/color] P%d %s · %s · %s" % [String(player.get("player_color","#9ca3a5")),
			int(player.player_id),String(player.get("player_name","Player")),String(player.faction_id).replace("_"," ").capitalize(),marker])
	players_label.text="\n".join(player_lines)
	var may_act:=winner_id==0 and not bool(turn.get("neutral_phase",false)) and int(turn.get("active_player",0))==session.local_player_id and session.status==NetworkSession.Status.ACTIVE
	send_button.disabled=not may_act; end_turn_button.disabled=not may_act
	revision_label.text="Synchronization revision: %d | Visibility revision: %d" % [int(snapshot.get("sync_revision",0)),int(snapshot.get("visibility_revision",0))]
	var own: Dictionary=snapshot.get("own_player",{})
	resources_label.text="Faction: %s | Resources: %s" % [String(own.get("faction_id","")),JSON.stringify(own.get("resources",{}))]
	var lines:=PackedStringArray(["[b]Your entities[/b]"])
	for entity: Dictionary in snapshot.get("owned_entities",[]):
		lines.append("#%d  %s  cell %d  HP %d/%d" % [int(entity.id),String(entity.definition_id),int(entity.cell_id),int(entity.hp),int(entity.max_hp)])
	lines.append("\n[b]Currently observed entities[/b]")
	for entity: Dictionary in snapshot.get("visible_entities",[]):
		if int(entity.controller_id)==session.local_player_id: continue
		lines.append("#%d  P%d %s  cell %d  HP %d/%d" % [int(entity.id),int(entity.controller_id),String(entity.definition_id),int(entity.cell_id),int(entity.hp),int(entity.max_hp)])
	lines.append("\n[b]Historical contacts[/b]")
	for contact: Dictionary in snapshot.get("known_contacts",[]):
		lines.append("#%d  last seen at cell %d" % [int(contact.contact_id),int(contact.last_known_cell_id)])
	lines.append("\n[b]Discovered sites[/b]")
	for site: Dictionary in snapshot.get("observed_sites",[]): lines.append("#%d  %s  cell %d" % [int(site.id),String(site.definition_id),int(site.cell_id)])
	if winner_id!=0:
		for player: Dictionary in snapshot.get("players",[]):
			if int(player.player_id)==winner_id:
				lines.append("\n[b]%s wins as %s in round %d after %ds.[/b]" % [String(player.get("player_name","Player")),
					String(player.faction_id).replace("_"," ").capitalize(),int(turn.get("round_number",0)),int(turn.get("match_duration_seconds",0))])
	entities_label.text="\n".join(lines)
