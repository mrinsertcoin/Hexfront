class_name MythicFrame
extends Node2D
## Shared engraved roots and hexagonal seals. No layout footprint or input.
const TITLE_FONT=preload("res://assets/fonts/cinzel_decorative/CinzelDecorative-Regular.ttf")
const GOLD=Color("b6a071")
const SHADOW=Color("574d37")
var target: Control
var compact: bool=false

static func apply(control: Control,small: bool=false) -> MythicFrame:
	var existing:=control.get_node_or_null("MythicFrame") as MythicFrame
	if existing!=null: return existing
	if control is PanelContainer:
		var original:=control.get_theme_stylebox("panel")
		var style:=original.duplicate() as StyleBoxFlat if original is StyleBoxFlat else StyleBoxFlat.new()
		style.content_margin_left=original.get_margin(SIDE_LEFT); style.content_margin_right=original.get_margin(SIDE_RIGHT)
		style.content_margin_top=original.get_margin(SIDE_TOP); style.content_margin_bottom=original.get_margin(SIDE_BOTTOM)
		style.bg_color=Color("111c19"); style.border_color=SHADOW
		style.set_border_width_all(1); style.set_corner_radius_all(9)
		style.shadow_color=Color(0,0,0,0.4); style.shadow_size=5
		control.add_theme_stylebox_override("panel",style)
	var frame:=MythicFrame.new(); frame.name="MythicFrame"; frame.target=control; frame.compact=small
	frame.z_index=8; control.add_child(frame)
	control.resized.connect(frame.queue_redraw)
	return frame

func _draw() -> void:
	if target==null or target.size.x<32 or target.size.y<24: return
	var extent:=target.size
	var band:=7.0 if compact else 18.0
	var corner:=minf(22.0 if compact else 48.0,minf(extent.x,extent.y)*0.22)
	var ink:=Color(GOLD,0.72 if compact else 0.9)
	for horizontal: bool in [true,false]:
		var length:=extent.x if horizontal else extent.y
		for opposite: bool in [false,true]:
			var offset: float=(extent.y if horizontal else extent.x)-4 if opposite else 4
			var start:=Vector2(corner,offset) if horizontal else Vector2(offset,corner)
			var finish:=Vector2(length-corner,offset) if horizontal else Vector2(offset,length-corner)
			draw_line(start,finish,SHADOW,1,true)
			if length<corner*2+32: continue
			var count:=maxi(1,floori((length-corner*2)/76.0))
			for index in range(count):
				var along:=corner+(length-corner*2)*(float(index)+0.5)/count
				var inward:=-1.0 if opposite else 1.0
				var center:=Vector2(along,offset) if horizontal else Vector2(offset,along)
				var tangent:=Vector2.RIGHT if horizontal else Vector2.DOWN
				var normal:=(Vector2.DOWN if horizontal else Vector2.RIGHT)*inward
				var width:=4.0 if compact else 6.0
				var depth:=3.0 if compact else 7.0
				draw_polyline(PackedVector2Array([center-tangent*width,center+normal*depth,center+tangent*width]),ink,1,true)
				if not compact:
					draw_polyline(PackedVector2Array([center-tangent*12,center-tangent*6+normal*10,center+normal*3,center+tangent*6+normal*10,center+tangent*12]),Color(GOLD,0.35),1,true)
	for sx: float in [1.0,-1.0]:
		for sy: float in [1.0,-1.0]:
			var origin:=Vector2(0 if sx>0 else extent.x,0 if sy>0 else extent.y)
			var knot:=PackedVector2Array()
			for point: Vector2 in [Vector2(corner,4),Vector2(band,4),Vector2(4,band),Vector2(4,corner)]: knot.append(origin+point*Vector2(sx,sy))
			draw_polyline(knot,ink,1.4,true)
			var weave:=PackedVector2Array()
			for point: Vector2 in [Vector2(corner,band*0.65),Vector2(band*1.3,band*0.65),Vector2(band*0.65,band*1.3),Vector2(band*0.65,corner)]: weave.append(origin+point*Vector2(sx,sy))
			draw_polyline(weave,Color(GOLD,0.48),1,true)
			_hex(origin+Vector2(band*0.65*sx,band*0.65*sy),2.3 if compact else 4.2,ink)
			if not compact:
				for distance: float in [26.0,36.0]:
					_leaf(origin+Vector2(distance*sx,9*sy),Vector2(sx,sy),ink)
					_leaf(origin+Vector2(9*sx,distance*sy),Vector2(sy,sx),ink)
	if not compact and extent.x>250:
		for y: float in [10.0,extent.y-10.0]:
			var center:=Vector2(extent.x*0.5,y)
			_hex(center,5.5,ink)
			draw_line(center-Vector2(34,0),center-Vector2(10,0),ink,1,true)
			draw_line(center+Vector2(10,0),center+Vector2(34,0),ink,1,true)

func _hex(center: Vector2,radius: float,color: Color) -> void:
	var points:=PackedVector2Array()
	for index in range(7): points.append(center+Vector2.from_angle(PI/6+index*TAU/6)*radius)
	draw_polyline(points,color,1,true); draw_circle(center,1,color)

func _leaf(center: Vector2,direction: Vector2,color: Color) -> void:
	var along:=direction.normalized()*5; var across:=along.orthogonal()*0.45
	draw_polyline(PackedVector2Array([center-along,center+across,center+along,center-across,center-along]),color,1,true)
