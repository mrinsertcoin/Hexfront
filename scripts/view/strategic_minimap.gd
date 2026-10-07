class_name StrategicMinimap
extends Control
## Fog-aware equirectangular strategy map; it never reads hidden contacts.

signal cell_focused(cell_id: int)
var state: GameState
var observation: TeamObservation
var viewer_id: int=-1
var camera_direction:=Vector3.LEFT

func _ready() -> void:
	custom_minimum_size=Vector2(250,125); mouse_filter=Control.MOUSE_FILTER_STOP

func configure(game_state: GameState,team_observation: TeamObservation,controller_id: int,direction: Vector3) -> void:
	state=game_state; observation=team_observation; viewer_id=controller_id; camera_direction=direction
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#091116"),true)
	if state==null or observation==null: return
	for cell: PlanetCell in state.grid.cells:
		if not observation.is_explored(cell.id): continue
		var color:=Color("#35444a")
		if observation.is_visible(cell.id): color=Color("#718a79")
		if state.is_water_cell(cell.id): color=Color("#234f70") if observation.is_visible(cell.id) else Color("#1b3348")
		draw_circle(_project(cell.up),1.8,color)
	for site: Dictionary in observation.observed_sites.values(): draw_circle(_project(state.grid.get_cell(int(site.cell_id)).up),2.5,Color("#d5af5d"))
	for entity: Dictionary in observation.visible_entities.values():
		var color:=_player_color(int(entity.controller_id))
		draw_circle(_project(state.grid.get_cell(int(entity.cell_id)).up),3.2,color)
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==viewer_id: draw_circle(_project(state.grid.get_cell(unit.cell_id).up),3.5,_player_color(viewer_id))
	var p:=_project(camera_direction); draw_arc(p,7.0,0,TAU,16,Color.WHITE,1.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and state!=null:
		var mouse_event:=event as InputEventMouseButton
		var uv: Vector2=mouse_event.position/size
		var longitude: float=uv.x*TAU-PI; var latitude: float=(0.5-uv.y)*PI
		var direction: Vector3=Vector3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude))
		cell_focused.emit(state.grid.find_cell(direction))
		accept_event()

func _project(direction: Vector3) -> Vector2:
	var d:=direction.normalized(); var longitude:=atan2(d.z,d.x); var latitude:=asin(clampf(d.y,-1.0,1.0))
	return Vector2((longitude+PI)/TAU*size.x,(0.5-latitude/PI)*size.y)

func _player_color(controller_id: int) -> Color:
	if state.players.has(controller_id) and not state.players[controller_id].ownership_color.is_empty(): return Color(state.players[controller_id].ownership_color)
	const COLORS: Array[Color]=[Color("#63c7ff"),Color("#ff6f69"),Color("#8bd17c"),Color("#d69cff")]
	return COLORS[posmod(state.turn_state.order.find(controller_id),COLORS.size())]
