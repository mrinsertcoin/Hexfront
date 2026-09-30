class_name BaumeisterState
extends RefCounted

var bridges: Dictionary[int,BridgeState]={}
var districts: Dictionary[int,DistrictState]={}
var origin_pillars: Dictionary[int,int]={}
var unpaid_maintenance: Dictionary[int,int]={}
var next_bridge_id: int=1
var next_district_id: int=1
var last_maintenance_serial: Dictionary[int,int]={}

func add_bridge(controller: int,a: int,b: int,path: Array[int],turns: int,max_hp: int) -> BridgeState:
	var bridge:=BridgeState.new(next_bridge_id,controller,a,b,path,turns,max_hp)
	next_bridge_id+=1; bridges[bridge.id]=bridge; return bridge

func add_district(controller: int,pillar: int,cell: int,definition: String,turns: int) -> DistrictState:
	var district:=DistrictState.new(next_district_id,controller,pillar,cell,definition,turns)
	next_district_id+=1; districts[district.id]=district; return district

func district_at(cell_id: int) -> DistrictState:
	for district: DistrictState in districts.values():
		if district.cell_id==cell_id: return district
	return null

func snapshot() -> Dictionary:
	var bridge_rows: Array[Dictionary]=[]; var district_rows: Array[Dictionary]=[]
	var ids:=bridges.keys(); ids.sort()
	for id: int in ids: bridge_rows.append(bridges[id].snapshot())
	ids=districts.keys(); ids.sort()
	for id: int in ids: district_rows.append(districts[id].snapshot())
	return {"bridges":bridge_rows,"districts":district_rows,"origin_pillars":origin_pillars.duplicate(true),
		"unpaid_maintenance":unpaid_maintenance.duplicate(true),"next_bridge_id":next_bridge_id,"next_district_id":next_district_id}
