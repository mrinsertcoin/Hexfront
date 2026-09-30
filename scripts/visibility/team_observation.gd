class_name TeamObservation
extends RefCounted
## Detached read-only-in-practice snapshot supplied to UI and decision makers.

var team_id: int
var revision: int
var visible_cells:=PackedByteArray()
var explored_cells:=PackedByteArray()
var detection_cells:=PackedByteArray()
var visible_entities: Dictionary[int,Dictionary]={}
var known_contacts: Dictionary[int,Dictionary]={}
var observed_sites: Dictionary[int,Dictionary]={}
var newly_observed_entity_ids: Array[int]=[]
var lost_entity_ids: Array[int]=[]
var newly_discovered_site_ids: Array[int]=[]

func get_visibility(cell_id: int) -> VisibilityState.CellVisibility:
	if cell_id<0 or cell_id>=visible_cells.size(): return VisibilityState.CellVisibility.UNEXPLORED
	if visible_cells[cell_id]!=0: return VisibilityState.CellVisibility.VISIBLE
	return VisibilityState.CellVisibility.EXPLORED if explored_cells[cell_id]!=0 else VisibilityState.CellVisibility.UNEXPLORED

func is_visible(cell_id: int) -> bool: return cell_id>=0 and cell_id<visible_cells.size() and visible_cells[cell_id]!=0
func is_explored(cell_id: int) -> bool: return cell_id>=0 and cell_id<explored_cells.size() and explored_cells[cell_id]!=0
func can_observe_entity(entity_id: int) -> bool: return visible_entities.has(entity_id)
func has_discovered_site(site_id: int) -> bool: return observed_sites.has(site_id)

func contact_at(cell_id: int) -> Dictionary:
	var ids: Array[int]=[]
	for id: int in known_contacts:
		if int(known_contacts[id].last_known_cell_id)==cell_id: ids.append(id)
	ids.sort()
	return known_contacts[ids[0]].duplicate(true) if not ids.is_empty() else {}
