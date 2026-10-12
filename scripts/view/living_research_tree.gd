class_name LivingResearchTree
extends Control
## Definition-driven root layout. Only selection intent leaves this canvas.

signal technology_selected(id: String)
const NAME_FONT=preload("res://assets/fonts/cinzel_decorative/CinzelDecorative-Regular.ttf")
const NODE_SIZE=Vector2(215,90)
const PITCH=Vector2(242,155)
const COLORS={"LOCKED":Color("9baa99"),"AVAILABLE":Color("dfcd8d"),"RESEARCHING":Color("e2eeb0"),"COMPLETED":Color("a0ccaa")}
var panel: StrategicResearchPanel
var node_buttons: Dictionary={}
var positions: Dictionary={}
var children_by_id: Dictionary={}
var edges: Array[PackedStringArray]=[]
var zoom: float=1.0
var leaf_cursor: float=0.0
var pulse: float=0.0
var tick: float=0.0

func rebuild(owner_panel: StrategicResearchPanel,ids: PackedStringArray,scale_factor: float) -> void:
	panel=owner_panel; zoom=scale_factor
	for child: Node in get_children(): remove_child(child); child.queue_free()
	node_buttons.clear(); positions.clear(); children_by_id.clear(); edges.clear(); leaf_cursor=0
	for id: String in ids: children_by_id[id]=[]
	var roots: Array[String]=[]
	for id: String in ids:
		var prerequisites:=panel.registry.technology(id).prerequisite_ids
		if prerequisites.is_empty(): roots.append(id)
		else:
			# First parent owns the layout; every prerequisite still receives a link.
			if children_by_id.has(prerequisites[0]): children_by_id[prerequisites[0]].append(id)
			for parent: String in prerequisites: edges.append(PackedStringArray([parent,id]))
	for id: String in roots: _place(id,0)
	var max_y:=0.0
	for id: String in ids:
		if not positions.has(id): continue
		var definition:=panel.registry.technology(id)
		var state_name:=panel.technology_state(id)
		var color: Color=COLORS[state_name]
		var button:=Button.new(); button.name=id; button.position=positions[id]*zoom; button.size=NODE_SIZE*zoom
		button.tooltip_text=StrategicTooltip.technology(definition,panel.registry)+"\n"+panel.locked_reason(id)
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		for state_style: String in ["normal","hover","pressed","focus"]:
			var style:=StyleBoxFlat.new(); style.bg_color=Color("17291e") if state_name!="LOCKED" else Color("182019")
			style.border_color=color if state_style!="normal" or id==panel.selected_id else color.darkened(0.4)
			style.set_border_width_all(2 if id==panel.selected_id or state_style=="focus" else 1)
			style.set_corner_radius_all(18); button.add_theme_stylebox_override(state_style,style)
		var names:=Label.new(); names.text=definition.display_name.replace(" (Provisional)",""); names.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		names.add_theme_font_override("font",NAME_FONT); names.add_theme_font_size_override("font_size",maxi(12,roundi(15*zoom))); names.add_theme_color_override("font_color",color)
		names.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; names.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		names.position=Vector2(10,5)*zoom; names.size=Vector2(195,55)*zoom; names.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(names)
		var status:=Label.new(); status.text="%s · %d RP" % [{"LOCKED":"LOCKED","AVAILABLE":"READY","RESEARCHING":"GROWING","COMPLETED":"GROWN"}[state_name],definition.research_cost]
		status.add_theme_font_size_override("font_size",maxi(10,roundi(12*zoom))); status.add_theme_color_override("font_color",color)
		status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; status.position=Vector2(4,64)*zoom; status.size=Vector2(207,22)*zoom
		status.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(status)
		button.pressed.connect(func(): technology_selected.emit(id)); add_child(button); node_buttons[id]=button
		max_y=maxf(max_y,positions[id].y+NODE_SIZE.y)
	custom_minimum_size=Vector2(maxf(leaf_cursor*PITCH.x+48,400),max_y+70)*zoom
	queue_redraw()

func update_selection() -> void:
	# Keep nodes (and keyboard focus) alive when only the inspection changes.
	for id: String in node_buttons:
		var button: Button=node_buttons[id]
		var color: Color=COLORS[panel.technology_state(id)]
		for state_style: String in ["normal","hover","pressed","focus"]:
			var style:=button.get_theme_stylebox(state_style) as StyleBoxFlat
			style.border_color=color if state_style!="normal" or id==panel.selected_id else color.darkened(0.4)
			style.set_border_width_all(2 if id==panel.selected_id or state_style=="focus" else 1)

func _place(id: String,depth: int) -> float:
	var branches: Array=children_by_id[id]
	var x: float
	if branches.is_empty(): x=leaf_cursor*PITCH.x+32; leaf_cursor+=1
	else:
		var first:=_place(branches[0],depth+1); var last:=first
		for index in range(1,branches.size()): last=_place(branches[index],depth+1)
		x=(first+last)*0.5
	positions[id]=Vector2(x,64+depth*PITCH.y)
	return x

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	pulse=fmod(pulse+delta*0.15,1.0); tick+=delta
	if tick>=0.08: tick=0; queue_redraw()

func _draw() -> void:
	if panel==null: return
	for edge: PackedStringArray in edges:
		if not positions.has(edge[0]) or not positions.has(edge[1]): continue
		var from: Vector2=(positions[edge[0]]+Vector2(NODE_SIZE.x*0.5,NODE_SIZE.y))*zoom
		var to: Vector2=(positions[edge[1]]+Vector2(NODE_SIZE.x*0.5,0))*zoom
		var curve:=Curve2D.new(); curve.add_point(from,Vector2.ZERO,Vector2(0,42)*zoom); curve.add_point(to,Vector2(0,-42)*zoom)
		var points:=curve.tessellate(5,3)
		var nourished:=panel.technology_state(edge[0])==StrategicResearchPanel.COMPLETED
		var color:=Color("94ad72") if nourished else Color("506045")
		draw_polyline(points,Color("0d130e"),10*zoom,true); draw_polyline(points,color.darkened(0.35),6*zoom,true); draw_polyline(points,color,1.5*zoom,true)
		# Fine rootlets make branches feel grown rather than like circuit wiring.
		for index in [8,16,24]:
			var spot:=curve.sample_baked(curve.get_baked_length()*float(index)/32.0)
			var side:=-1.0 if index==16 else 1.0
			draw_polyline(PackedVector2Array([spot,spot+Vector2(12*side,9)*zoom,spot+Vector2(20*side,23)*zoom]),color.darkened(0.25),zoom,true)
		if nourished: draw_circle(curve.sample_baked(curve.get_baked_length()*pulse),3*zoom,Color("d3dba1"))
	# A spreading crown above the first root, with leafy tendrils.
	for id: String in positions:
		if not panel.registry.technology(id).prerequisite_ids.is_empty(): continue
		var crown: Vector2=(positions[id]+Vector2(NODE_SIZE.x*0.5,-7))*zoom
		for side: float in [-1.0,1.0]:
			draw_polyline(PackedVector2Array([crown,crown+Vector2(45*side,-15)*zoom,crown+Vector2(95*side,-8)*zoom]),Color("8b9e62"),2*zoom,true)
			for leaf in range(1,5): draw_circle(crown+Vector2((20+leaf*15)*side,-19+leaf%2*7)*zoom,3*zoom,Color("8b9e62"))
