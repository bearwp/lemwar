extends Node

# Global references to important game systems
var world_chat: WorldChat = null
var game_map: GameMap = null
var debug_ui: DebugUI = null

# Called when the singleton is instantiated
func _ready() -> void:
	print("GameState singleton initialized")

# Convenience methods
func register_world_chat(chat: WorldChat) -> void:
	world_chat = chat
	print("WorldChat registered with GameState")

func register_game_map(map: GameMap) -> void:
	game_map = map
	print("GameMap registered with GameState")

func register_debug_ui(ui: DebugUI) -> void:
	debug_ui = ui
	print("DebugUI registered with GameState")
