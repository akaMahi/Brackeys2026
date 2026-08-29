extends Area2D
class_name PlayerDetectionArea

# A wide trigger zone around the player that spawners (car_spawner.gd)
# watch for. Attach this to an Area2D placed as a CHILD of your player
# car scene, and add your own CollisionShape2D to it, sized however wide
# you want the detection range to be — resize it visually in the editor
# instead of tuning a number (a CircleShape2D is the natural choice, but
# any shape works).
#
# SETUP:
# 1. Add an Area2D as a child of your player car scene, attach this script.
# 2. Add a CollisionShape2D child to THAT Area2D with whatever shape/size
#    you want the detection range to be.
# 3. Set this Area2D's collision LAYER (not mask) to whatever you want
#    spawners to watch for — default layer 1. A spawner detects this area
#    by having that same layer bit set in ITS OWN collision mask.

@export var detection_group: String = "player_detection" # must match car_spawner.gd's player_detection_group


func _ready() -> void:
	monitoring = false # this side never needs to detect anything itself, only BE detected
	monitorable = true
	add_to_group(detection_group)
