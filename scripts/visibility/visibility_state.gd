class_name VisibilityState
extends RefCounted

enum CellVisibility { UNEXPLORED, EXPLORED, VISIBLE }

var team_id: int
var explored_cells:=PackedByteArray()
var visible_cells:=PackedByteArray()
var detection_cells:=PackedByteArray()
var visible_entities: Dictionary[int,Dictionary]={}
var known_contacts: Dictionary[int,KnownContact]={}
var observed_sites: Dictionary[int,Dictionary]={}
var last_visible_hostiles: Dictionary[int,Dictionary]={}
var new_entity_ids: Array[int]=[]
var lost_entity_ids: Array[int]=[]
var new_site_ids: Array[int]=[]
var visibility_revision: int=0

func _init(id: int=0,cell_count: int=0) -> void:
	team_id=id; resize(cell_count)

func resize(cell_count: int) -> void:
	explored_cells.resize(cell_count); explored_cells.fill(0)
	visible_cells.resize(cell_count); visible_cells.fill(0)
	detection_cells.resize(cell_count); detection_cells.fill(0)

func clear_runtime() -> void:
	visible_cells.fill(0); detection_cells.fill(0); visible_entities.clear()
	new_entity_ids.clear(); lost_entity_ids.clear(); new_site_ids.clear()

func get_visibility(cell_id: int) -> CellVisibility:
	if cell_id<0 or cell_id>=visible_cells.size(): return CellVisibility.UNEXPLORED
	if visible_cells[cell_id]!=0: return CellVisibility.VISIBLE
	return CellVisibility.EXPLORED if explored_cells[cell_id]!=0 else CellVisibility.UNEXPLORED

func is_visible(cell_id: int) -> bool: return cell_id>=0 and cell_id<visible_cells.size() and visible_cells[cell_id]!=0
func is_explored(cell_id: int) -> bool: return cell_id>=0 and cell_id<explored_cells.size() and explored_cells[cell_id]!=0
func is_detected(cell_id: int) -> bool: return cell_id>=0 and cell_id<detection_cells.size() and detection_cells[cell_id]!=0
