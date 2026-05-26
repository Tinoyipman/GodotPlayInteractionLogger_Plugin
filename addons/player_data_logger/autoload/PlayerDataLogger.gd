## PlayerDataLogger.gd  (Autoload singleton: "PlayerDataLogger")
##
## Records player interactions (clicks, drags, key presses) to a local CSV
## and optionally syncs each row to a Google Sheets Apps Script endpoint.
##
## All game-specific dependencies have been replaced with @export properties
## and override-able virtual methods so the logger works in any project.
##
## ── Quick Start ──────────────────────────────────────────────────────────────
##
##   1. Add this script as an Autoload (e.g. "PlayerDataLogger").
##   2. Set google_script_url to your Apps Script Web App URL.
##   3. Call PlayerDataLogger.set_logging_enabled(true) to start recording.
##   4. Override _get_game_version() and _get_loop_label() if your project
##      tracks those values, or leave them as-is for sensible defaults.
##
## ── Interaction Areas ────────────────────────────────────────────────────────
##   By default the logger recognises a node named "InteractionArea" as a
##   transparent click-target whose *parent* is the logical object.
##   Change interaction_area_node_name to match your own naming convention,
##   or override _find_clicked_object() entirely for full control.
##
## ── Disabling cloud sync ─────────────────────────────────────────────────────
##   Leave google_script_url empty ("") and only local CSV logging is used.
##
## ─────────────────────────────────────────────────────────────────────────────

extends Node

# ---------------------------------------------------------------------------
# Configuration exports — set these in the Inspector or from code
# ---------------------------------------------------------------------------

## Google Apps Script Web App URL.
## Leave empty to disable cloud sync (local CSV only).
@export var google_script_url: String = ""

## Path for the local CSV backup log.
@export var log_file_path: String = "user://playtest_log.csv"

## Path where the persistent user ID is stored between sessions.
@export var id_file_path: String = "user://user_id.txt"

## Pixel distance the mouse must travel before a press is treated as a drag.
@export var drag_threshold: float = 10.0

## CSV column headers. Change order or add columns here — make sure
## _build_entry() returns values in the same order.
@export var csv_headers: Array[String] = [
	"Timestamp", "UserID", "GameVersion", "Loop", "Scene", "Interaction", "Object"
]

## Name of the node used as a transparent click-target in your scenes.
## The logger will return that node's *parent* as the interacted object.
@export var interaction_area_node_name: String = "InteractionArea"

## HTTP timeout in seconds for cloud sync requests.
@export var http_timeout: float = 15.0

## Maximum redirects to follow (Google Apps Script redirects once by default).
@export var http_max_redirects: int = 10

# ---------------------------------------------------------------------------
# Runtime toggles
# ---------------------------------------------------------------------------

## Master switch. When false, _log_interaction() is a no-op.
var logging_enabled: bool = false

func set_logging_enabled(enabled: bool) -> void:
	logging_enabled = enabled

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _http_request: HTTPRequest
var _request_queue: Array = []
var _is_queue_processing: bool = false
var _user_id: String = "Unknown"

var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_start_object: String = "null"
var _is_dragging: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_user_id = _get_or_create_user_id()

	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.timeout = http_timeout
	_http_request.max_redirects = http_max_redirects
	_http_request.accept_gzip = false
	_http_request.request_completed.connect(_on_request_completed)

	if not FileAccess.file_exists(log_file_path):
		_write_to_file(csv_headers)


func _input(event: InputEvent) -> void:
	if not logging_enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start_pos = event.position
			_drag_start_object = _find_clicked_object()
		else:
			if _is_dragging:
				_log_interaction("Mouse Drag (End)",
					_drag_start_object + " -> " + _find_clicked_object())
				_is_dragging = false
			else:
				_log_interaction("Mouse Click", _drag_start_object)
			_drag_start_object = "null"

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_log_interaction("Key Press", "Enter")

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if not _is_dragging and event.position.distance_to(_drag_start_pos) > drag_threshold:
			_is_dragging = true
			_log_interaction("Mouse Drag (Start)", _drag_start_object)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Log a custom interaction from anywhere in your game.
## [param type]        Short label, e.g. "Button Press", "Item Collected".
## [param object_info] Additional context, e.g. the object or item name.
func log(type: String, object_info: String = "") -> void:
	_log_interaction(type, object_info)


## Return the current user ID (generated once per device).
func get_user_id() -> String:
	return _user_id

# ---------------------------------------------------------------------------
# Virtual methods — override in a subclass or via Callable for project hooks
# ---------------------------------------------------------------------------

## Return a string describing the current game version.
## Override this to pull from your own version system.
func _get_game_version() -> String:
	return "v1.0"


## Return a string describing the current loop / run / session count.
## Override this to pull from your own flow manager.
func _get_loop_label() -> String:
	return "Loop 1"

# ---------------------------------------------------------------------------
# Internal — logging
# ---------------------------------------------------------------------------

func _log_interaction(type: String, object_info: String) -> void:
	if not logging_enabled:
		return

	var entry := _build_entry(type, object_info)
	_write_to_file(entry)

	if not google_script_url.is_empty():
		_request_queue.append(entry)
		_process_queue()


## Builds a row array matching csv_headers. Override to add/remove columns.
func _build_entry(type: String, object_info: String) -> Array:
	var timestamp := Time.get_datetime_string_from_system()
	var current_scene := get_tree().current_scene
	var scene_name := current_scene.name if current_scene else "Global"

	return [
		timestamp,
		_user_id,
		_get_game_version(),
		_get_loop_label(),
		scene_name,
		type,
		object_info,
	]

# ---------------------------------------------------------------------------
# Internal — object detection
# ---------------------------------------------------------------------------

## Returns the name of the UI element or 2D physics object under the cursor.
## Override this method for custom hit-detection logic.
func _find_clicked_object() -> String:
	# 1. UI layer takes priority
	var gui_obj := get_viewport().gui_get_hovered_control()
	if gui_obj:
		return "UI_" + gui_obj.name

	# 2. 2D physics world
	var current_scene := get_tree().current_scene
	if not current_scene:
		return "null"

	var world_2d = current_scene.get_world_2d()
	if not world_2d:
		return "null"

	var params := PhysicsPointQueryParameters2D.new()
	params.position = current_scene.get_global_mouse_position()
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var results = world_2d.direct_space_state.intersect_point(params)

	for result in results:
		var collider = result.collider
		if not collider:
			continue
		return _resolve_object_name(collider)

	return "null"


## Maps a physics collider to a human-readable object name.
## Handles the InteractionArea convention — change interaction_area_node_name
## to match your project, or override this for a different structure.
func _resolve_object_name(collider: Node) -> String:
	var area_name := interaction_area_node_name

	# Collider IS the interaction area node → return its parent
	if collider.name == area_name:
		return collider.get_parent().name

	# Collider is a child of the interaction area node → return grandparent
	var parent := collider.get_parent()
	if parent and parent.name == area_name:
		return parent.get_parent().name

	# Default: return the collider's own name
	return collider.name

# ---------------------------------------------------------------------------
# Internal — persistence
# ---------------------------------------------------------------------------

func _get_or_create_user_id() -> String:
	if FileAccess.file_exists(id_file_path):
		var file := FileAccess.open(id_file_path, FileAccess.READ)
		var id := file.get_as_text().strip_edges()
		file.close()
		return id

	var chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var new_id := "USR-"
	for i in range(10):
		new_id += chars[randi() % chars.length()]

	var file := FileAccess.open(id_file_path, FileAccess.WRITE)
	file.store_string(new_id)
	file.close()
	return new_id


func _write_to_file(data: Array) -> void:
	var file := FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
	else:
		file.seek_end()
	file.store_line(",".join(data))
	file.close()

# ---------------------------------------------------------------------------
# Internal — HTTP queue
# ---------------------------------------------------------------------------

func _process_queue() -> void:
	if _is_queue_processing or _request_queue.is_empty():
		return

	_is_queue_processing = true
	var row_data: Array = _request_queue.pop_front()

	var payload := JSON.stringify({"row_data": row_data})
	var headers := PackedStringArray()

	var error := _http_request.request(
		google_script_url, headers, HTTPClient.METHOD_POST, payload
	)

	if error != OK:
		_is_queue_processing = false
		await get_tree().create_timer(1.0).timeout
		_process_queue()


func _on_request_completed(_result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_is_queue_processing = false
	if response_code != 200:
		push_warning("[PlayerDataLogger] Cloud sync failed. HTTP %d" % response_code)
	_process_queue()
