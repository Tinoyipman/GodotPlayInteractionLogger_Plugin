@tool
extends EditorPlugin

const AUTOLOAD_NAME := "PlayerDataLogger"
const AUTOLOAD_PATH := "res://addons/player_data_logger/autoload/PlayerDataLogger.gd"

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	print("[Player Data Logger] Plugin enabled. PlayerDataLogger autoload registered.")

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	print("[Player Data Logger] Plugin disabled.")
