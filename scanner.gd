# LidarScanner.gd
extends Node3D

## Number of points in a full horizontal sweep.
@export var horizontal_resolution = 256
## Number of vertical laser layers.
@export var vertical_resolution = 64
## Maximum range of the scanner in meters.
@export var max_range = 120.0
## Sensitivity of the mouse for camera rotation.
@export var mouse_sensitivity = 0.15
@export var min_color_dist = 0.0
@export var max_color_dist = 5.0

# --- Node References ---
# Assign these in the Inspector or ensure they are children of this node.
@onready var camera_3d: Camera3D = $Camera3D
@onready var multi_mesh_instance: MultiMeshInstance3D = $"../MultiMeshInstance3D"

var point_cloud_data: Array = []
var instance_count: int = 0

func _ready():
	# IMPORTANT: For color to work, you MUST select the MultiMesh resource
	# in the Inspector and set its "Use Colors" property to true.
	
	# Initialize the MultiMesh for real-time visualization.
	instance_count = horizontal_resolution * vertical_resolution
	multi_mesh_instance.multimesh.instance_count = instance_count
	
	# Generate the scan once at the beginning, as it is now static.
	generate_and_visualize_scan()

func _input(event: InputEvent):
	if event is InputEventMouseButton and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Handle mouse motion for camera rotation only.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# FPS-style controls:
		# Horizontal rotation (yaw) affects the parent Node3D (self).
		self.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		
		# Vertical rotation (pitch) affects the camera directly.
		camera_3d.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		
		# Clamp vertical rotation to prevent flipping over (-90 to 90 degrees).
		var camera_rot = camera_3d.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, 0, 90)
		camera_3d.rotation_degrees = camera_rot

	# Press Escape to release the mouse cursor.
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Press the "Accept" key (Enter/Space) to save the last full scan.
	if Input.is_action_just_pressed("ui_accept"):
		save_to_file("point_cloud_categorized.txt")

func generate_and_visualize_scan():
	point_cloud_data.clear()
	var space_state = get_world_3d().direct_space_state
	
	# --- Top Hemisphere Scan Logic ---
	var v_angle_step = (PI / 2.0) / vertical_resolution # Cover 90 degrees vertically
	var instance_index = 0

	# Get the SENSOR's stationary rotational basis to orient the scan correctly.
	var basis = self.global_transform.basis

	for i in range(vertical_resolution):
		var v_angle = i * v_angle_step # Starts from 0 (horizon) to PI/2 (up)
		for j in range(horizontal_resolution):
			var h_angle = (2.0 * PI / horizontal_resolution) * j

			# 1. Calculate the direction vector in LOCAL space.
			var local_dir = Vector3(
				cos(v_angle) * sin(h_angle),
				sin(v_angle),
				cos(v_angle) * cos(h_angle)
			).normalized()

			# 2. Transform the local direction into a GLOBAL direction using the sensor's rotation.
			var global_dir = basis * local_dir

			# 3. Perform the raycast from the SENSOR's stationary position.
			var query = PhysicsRayQueryParameters3D.create(self.global_position, self.global_position + global_dir * max_range)
			var result = space_state.intersect_ray(query)

			if result:
				# --- Color by distance ---
				var distance = self.global_position.distance_to(result.position)
				# Interpolate from 0 (green) to 1 (red) based on distance
				var t = clamp((distance - min_color_dist) / (max_color_dist - min_color_dist), 0.0, 1.0)
				var point_color = Color.GREEN.lerp(Color.RED, t)
				multi_mesh_instance.multimesh.set_instance_color(instance_index, point_color)

				# Store data for saving later.
				var collider = result.collider
				var object_name = collider.name if collider else "Unknown"
				point_cloud_data.append({"pos": result.position, "name": object_name})
				
				# Convert the global hit position to the local space of the MultiMeshInstance.
				var local_hit_pos = multi_mesh_instance.to_local(result.position)
				var hit_transform = Transform3D(Basis(), local_hit_pos)
				multi_mesh_instance.multimesh.set_instance_transform(instance_index, hit_transform)
			else:
				# If a ray doesn't hit, hide its corresponding mesh instance.
				var hidden_transform = Transform3D(Basis(), Vector3(0, -1000, 0))
				multi_mesh_instance.multimesh.set_instance_transform(instance_index, hidden_transform)
				# Also set its color to transparent.
				multi_mesh_instance.multimesh.set_instance_color(instance_index, Color(0,0,0,0))
			
			instance_index += 1

func save_to_file(file_path: String):
	if point_cloud_data.is_empty():
		print("Point cloud data is empty. Nothing to save.")
		return

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open file for writing.")
		return

	for point_data in point_cloud_data:
		file.store_line("%f %f %f %s" % [point_data.pos.x, point_data.pos.y, point_data.pos.z, point_data.name])

	print("Successfully saved %d points to %s" % [point_cloud_data.size(), file_path])
