extends Node
## SnapshotSystem — auto-snapshots and rollback
## Stub for Phase 1

var state_engine: Node  # StateEngine


func save_snapshot(name: String = "") -> Dictionary:
	if not state_engine:
		return {"error": "No state engine"}
	var snap_name := name if name != "" else "snap_%d" % Time.get_unix_time_from_system()
	print("[SnapshotSystem] Saved snapshot: %s" % snap_name)
	return {"ok": true, "name": snap_name}


func list_snapshots() -> Array:
	return []


func restore_snapshot(name: String) -> Dictionary:
	return {"error": "Not implemented"}
