extends Area2D
class_name CameraBox

# One "fixed view" for the camera-box system in camera.gd.
#
# SETUP:
# 1. Attach this script to an Area2D.
# 2. Add a CollisionShape2D child sized to the region this view should cover.
# 3. Add this node to the "camera_box" group (Node → Groups panel).
# 4. Set this Area2D's collision LAYER to whatever you like (e.g. a
#    dedicated "camera_boxes" layer), and its collision MASK to include
#    the layer your player's car is on — otherwise body_entered never fires.
# 5. Position this node at the exact point you want the camera centered on
#    while the car is inside it — its global_position IS the camera target.

signal player_entered(box: CameraBox)

@export var player_group: String = "player" # the car must be in this group to trigger the box


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(player_group):
		player_entered.emit(self)
