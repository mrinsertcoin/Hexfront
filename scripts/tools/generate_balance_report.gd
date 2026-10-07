extends SceneTree

func _init() -> void:
	var registry:=ContentRegistry.new()
	var errors:=registry.validate()
	if not errors.is_empty():
		push_error("Cannot generate balance report: "+"; ".join(errors))
		quit(1); return
	var file:=FileAccess.open("res://docs/Balance_Alpha01.md",FileAccess.WRITE)
	if file==null:
		push_error("Cannot write docs/Balance_Alpha01.md")
		quit(1); return
	file.store_string(BalanceAnalysis.generate_report(registry))
	file.close()
	print("Generated docs/Balance_Alpha01.md")
	quit()
