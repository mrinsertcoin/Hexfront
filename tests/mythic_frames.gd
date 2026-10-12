extends SceneTree
const Main=preload("res://scenes/main.tscn")
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var app:=Main.instantiate() as AppController; root.add_child(app); await process_frame
	for screen: String in ["main","setup","options","multiplayer","host","join"]:
		match screen:
			"main": app.show_main_menu()
			"setup": app.show_match_setup()
			"options": app.show_options(false)
			"multiplayer": app.show_multiplayer_menu()
			"host": app.show_host_setup()
			"join": app.show_join_setup()
		await process_frame; await process_frame
		var frames:=app.menu_layer.find_children("MythicFrame","Node2D",true,false)
		check(frames.size()==1,screen+" has exactly one shared frame")
		if frames.size()!=1: continue
		var frame:=frames[0] as MythicFrame
		check(frame!=null and not frame.compact,screen+" uses the elaborate page pattern")
		check(frame.target.get_global_rect().end.x<=root.size.x and frame.target.get_global_rect().end.y<=root.size.y,screen+" fits viewport")
		check(MythicFrame.apply(frame.target)==frame,screen+" decoration is idempotent")
	var panel:=PanelContainer.new(); root.add_child(panel)
	var label:=Label.new(); label.text="City"; panel.add_child(label); await process_frame
	var before:=panel.get_combined_minimum_size()
	var frame:=MythicFrame.apply(panel,true); await process_frame
	check(frame.compact and not frame.is_class("Control"),"Compact city ornament cannot intercept mouse events")
	check(panel.get_combined_minimum_size()==before,"Ornament does not change layout minimum")
	panel.size=Vector2(340,200); await process_frame
	check(frame.target.size==Vector2(340,200),"Pattern follows panel resize")
	var research:=StrategicResearchPanel.new(); root.add_child(research)
	var state:=GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","baumeister"]})
	research.size=Vector2(1150,620); research.configure(GameRules.new(state),1); await process_frame
	check(research.get_node_or_null("MythicFrame") is MythicFrame,"Research shares page ornament")
	check(research.mouse_filter==Control.MOUSE_FILTER_STOP,"Research retains modal input protection")
	research.configure(GameRules.new(state),2); await process_frame
	check(research.get_node_or_null("MythicFrame") is MythicFrame,"Both factions retain identical frame family")
	panel.queue_free(); research.queue_free(); app.queue_free(); await process_frame
	print("Mythic frame checks complete; checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
