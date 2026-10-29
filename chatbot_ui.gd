extends Control

@onready var chat_display: RichTextLabel = $"VBoxContainer/ChatDisplay"
@onready var chat_input: LineEdit = $"VBoxContainer/ChatInput"

@onready var current_ai: NobodyWhoChat = WorldChat.new()



func _ready():
	current_ai.model_node = $NobodyWhoModel
	current_ai.map_node = $"../Map"
	
	chat_input.text_submitted.connect(_on_chat_input_text_submitted)
	current_ai.connect("response_updated", _on_response_updated)
	
	add_child(current_ai)
	current_ai.start_worker()
	
	State.register_world_chat(current_ai)

func _on_chat_input_text_submitted(text: String):
	chat_display.clear()
	current_ai.reset_context()
	if text.is_empty():
		return

	current_ai.say(text) # Pass the actual user text
	print("Sending to AI: " + text)
	chat_display.append_text("[b]You:[/b] %s\n" % text)
	chat_input.clear()


	# Placeholder for sending message to chatbot
	var bot_response = "(%s: )" % current_ai.name
	chat_display.append_text("[b]Bot:[/b] %s\n" % bot_response)
	chat_display.scroll_to_line(chat_display.get_line_count() - 1)

func _on_response_updated(response: String):
	print("AI Response: " + response)
	chat_display.append_text(response)
	chat_display.scroll_to_line(chat_display.get_line_count() - 1)
	
