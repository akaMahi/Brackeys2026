extends Area2D
class_name CameraBox

# One "fixed view" for the camera-box system in camera.gd.
#
# SETUP:
# 1. Attach this script to an Area2D.
# 2. Add a CollisionShape2D child using a RectangleShape2D, sized to the
#    region this view should cover. get_bounds() below reads its size
#    directly, so the trigger area and the camera's follow-clamp always
#    match without configuring anything twice.
# 3. Add this node to the "camera_box" group (Node → Groups panel).
# 4. Set this Area2D's collision MASK to include whichever layer your
#    player's car is on — otherwise body_entered never fires.

signal player_entered(box: CameraBox)

@export var player_group: String = "player" # the car must be in this group to trigger the box
@export var fallback_size: Vector2 = Vector2(960, 540) # used only if no RectangleShape2D is found


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(player_group):
		player_entered.emit(self)


func get_bounds() -> Rect2:
	var shape_node := _get_collision_shape()
	if shape_node and shape_node.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = shape_node.shape
		var half_size: Vector2 = rect_shape.size * 0.5
		var center: Vector2 = global_position + shape_node.position
		return Rect2(center - half_size, rect_shape.size)

	return Rect2(global_position - fallback_size * 0.5, fallback_size)


func _get_collision_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child
	return null
