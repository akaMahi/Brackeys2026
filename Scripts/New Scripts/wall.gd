extends StaticBody2D
class_name CarWall

@export_group("Knockback")
@export var knockback_strength: float = 150.0
@export var max_knockback_speed: float = 400.0
@export var minimum_impact_speed: float = 20.0

@export_group("Collision")
@export var player_group: String = "player"
@export var enemy_group: String = "enemy_car"


func _physics_process(_delta: float) -> void:
	# StaticBody2D itself does not emit collision signals.
	# Cars detect this wall through move_and_slide().
	pass
