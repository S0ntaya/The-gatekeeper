extends Control

@onready var start_button: Button = %StartButton
@onready var credit_button: Button = %CreditButton

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	credit_button.pressed.connect(_on_credit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_credit_pressed() -> void:
	get_tree().change_scene_to_file("res://Credit.tscn")
