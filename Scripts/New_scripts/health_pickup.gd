extends Area2D
class_name HealthPickup

# SETUP: attach to an Area2D with a CollisionShape2D. Set the Area2D's
# collision mask to include whatever layer the player's car is on, or
# body_entered will never fire.

@export var heal_amount: float = 25.0
@export var player_group: String = "player"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(player_group):
		return

	if body.has_method("heal"):
		body.heal(heal_amount)

	queue_free()
