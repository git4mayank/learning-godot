extends Node

class_name PetSelectorManager

signal pet_spawned(pet_instance: Node2D)
signal pet_selection_changed(pet_id: String)

@export_category("Pet Database")
@export var available_pets: Array[Resource] = []
@export var spawn_parent_path: NodePath = NodePath("../")
@export var default_pet_index: int = 0

@export_category("UI Integration")
@export var ui_selector_path: NodePath = NodePath("CanvasLayer/PetSelectorUI")

# Internal state
var current_pet_instance: Node2D = null
var current_selected_index: int = 0
var spawn_parent_node: Node = null

func _ready() -> void:
	_initialize_spawn_parent()
	if available_pets.size() > 0:
		current_selected_index = clamp(default_pet_index, 0, available_pets.size() - 1)
		call_deferred("_spawn_initial_pet")

func _initialize_spawn_parent() -> void:
	if not spawn_parent_path.is_empty():
		spawn_parent_node = get_node_or_null(spawn_parent_path)
	
	if spawn_parent_node == null:
		spawn_parent_node = get_tree().current_scene

func _spawn_initial_pet() -> void:
	spawn_pet_by_index(current_selected_index)

func spawn_pet_by_index(index: int) -> void:
	if available_pets.is_empty():
		push_warning("[PetSelector] Cannot spawn pet: available_pets array is empty!")
		return
		
	var safe_index = wrapi(index, 0, available_pets.size())
	var pet_resource = available_pets[safe_index]
	
	if pet_resource == null or not (pet_resource is PackedScene):
		push_error("[PetSelector] Invalid PackedScene resource at index: %d" % safe_index)
		return

	# Remove existing active pet if present
	if current_pet_instance and is_instance_valid(current_pet_instance):
		current_pet_instance.queue_free()

	# Instantiate and spawn the new pet
	var new_pet = (pet_resource as PackedScene).instantiate() as Node2D
	if new_pet:
		# Position near player or selector owner
		var player = _get_player_reference()
		if player:
			new_pet.global_position = player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		
		spawn_parent_node.add_child(new_pet)
		current_pet_instance = new_pet
		current_selected_index = safe_index
		
		var pet_id = new_pet.name
		if "pet_name" in new_pet:
			pet_id = new_pet.pet_name
			
		emit_signal("pet_spawned", new_pet)
		emit_signal("pet_selection_changed", pet_id)
		print("[PetSelector] Successfully spawned pet index: %d (%s)" % [safe_index, pet_id])

func next_pet() -> void:
	if available_pets.is_empty():
		return
	var next_index = (current_selected_index + 1) % available_pets.size()
	spawn_pet_by_index(next_index)

func previous_pet() -> void:
	if available_pets.is_empty():
		return
	var prev_index = (current_selected_index - 1 + available_pets.size()) % available_pets.size()
	spawn_pet_by_index(prev_index)

func _get_player_reference() -> Node2D:
  var players = get_tree().get_nodes_in_group("player")
  if players.size() > 0:
      return players[0] as Node2D
  return null

func get_active_pet() -> Node2D:
  return current_pet_instance