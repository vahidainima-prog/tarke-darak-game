extends Node3D

# Godot 4.x — visual mechanics test. Side camera looks along -Z.
# Feint depth: negative Z is BEHIND the attacker; positive Z is IN FRONT.
const BUILD_LABEL := "v6.3 - forward bending elbows"
const DEF_X := 1.55
const MIN_X := -4.7
const MAX_X := 0.35
const MIN_FIGHTER_GAP := 1.12
const DEFENDER_MIN_X := 0.65
const DEFENDER_MAX_X := 3.35
const SWING_SECONDS := 0.82
const RECOVERY_SECONDS := 0.48
const MAX_SWEEP_STEP := 0.025
const FEINT_DEPTH_LIMIT := 0.60
const SWING_ACCEL := 10.0 # normalized phase acceleration / s^2
const SWING_BRAKE := 14.0
const SWING_MAX_SPEED := 2.35 # normalized phase / s
const STICK_LENGTH := 2.15
const STICK_RADIUS := 0.055
const GUARD_RADIUS := 0.09

var attacker: Node3D
var defender: Node3D
var terkeh: MeshInstance3D
var darak: MeshInstance3D
var tip_debug: MeshInstance3D
var attack_x := -2.7
var defender_x := DEF_X
var swing := -1.0
var swing_finished := false
var recovery := -1.0
var recovery_from := 1.0
var guard_velocity := 0.0
var swing_outcome := ""
var defending := false
var opponent_delay := -1.0
var feint_depth := 0.0
var feint_target := 0.0
var guard_shift := 0.0
var guard_target := 0.0
var score_hit := 0
var score_block := 0
var status: Label
var header: Label
var detail: Label
var attack_hand_a: MeshInstance3D
var attack_hand_b: MeshInstance3D
var defend_hand: MeshInstance3D
var defend_hand_b: MeshInstance3D
var attack_arm_a: MeshInstance3D
var attack_arm_b: MeshInstance3D
var defend_arm: MeshInstance3D
var defend_arm_b: MeshInstance3D
var attack_forearm_a: MeshInstance3D
var attack_forearm_b: MeshInstance3D
var defend_forearm_a: MeshInstance3D
var defend_forearm_b: MeshInstance3D
var attack_elbow_a: MeshInstance3D
var attack_elbow_b: MeshInstance3D
var defend_elbow_a: MeshInstance3D
var defend_elbow_b: MeshInstance3D
var last_outcome := ""
var active_attack := false
var swing_speed := 0.0
var impact_hold := 0.0
var impact_message := ""
var strike_side := 1 # 1: right-hand release, -1: left-hand release
var release_blend := 0.0
var attack_step_phase := 0.0
var defend_step_phase := 0.0
var last_attack_x := -2.7
var last_defender_x := DEF_X
var game_camera: Camera3D
var shoulder_camera := false
var camera_focus := Vector3(0, 1.45, 0)

func material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.87
	return m

func block(parent: Node3D, name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = material(color)
	parent.add_child(n)
	n.position = at
	return n

func rod(parent: Node3D, name: String, radius: float, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	n.mesh = mesh
	n.material_override = material(color)
	parent.add_child(n)
	return n

func place_rod(n: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var v := b - a
	n.position = (a + b) * 0.5
	if v.length() > 0.001:
		n.quaternion = Quaternion(Vector3.UP, v.normalized())
	(n.mesh as CylinderMesh).height = maxf(v.length(), 0.01)

func place_two_bone_arm(upper: MeshInstance3D, lower: MeshInstance3D, elbow_mesh: MeshInstance3D, shoulder: Vector3, hand: Vector3, elbow_hint: Vector3) -> void:
	# Analytic two-bone IK: law of cosines with a consistent elbow bend plane.
	# The hand remains locked to the grip; the elbow is solved, not drawn as a straight stick.
	var upper_len := 0.90
	var lower_len := 0.90
	var to_hand := hand - shoulder
	var distance := maxf(to_hand.length(), 0.001)
	var forward := to_hand / distance
	var bend := elbow_hint - forward * elbow_hint.dot(forward)
	if bend.length_squared() < 0.0001:
		bend = Vector3.FORWARD - forward * Vector3.FORWARD.dot(forward)
	bend = bend.normalized()
	var reach := minf(distance, upper_len + lower_len - 0.002)
	var along := (reach * reach + upper_len * upper_len - lower_len * lower_len) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper_len * upper_len - along * along))
	var elbow := shoulder + forward * along + bend * height
	place_rod(upper, shoulder, elbow)
	place_rod(lower, elbow, hand)
	elbow_mesh.position = elbow

func person(name: String, x: float, face_right: bool) -> Node3D:
	var root := Node3D.new()
	root.name = name
	add_child(root)
	root.position.x = x
	var cloth := Color(0.94, 0.90, 0.77)
	var black := Color(0.085, 0.083, 0.075)
	var skin := Color(0.65, 0.45, 0.32)
	# Waist pivot: torso, chogha, stripes and head share a single transform.
	var waist := Node3D.new()
	waist.name = "WaistJoint"
	root.add_child(waist)
	waist.position = Vector3(0, 1.14, 0)
	block(waist, "Chogha", Vector3(0.62, 0.90, 0.38), Vector3(0, 0.43, 0), cloth)
	block(waist, "Chogha collar", Vector3(0.66, 0.10, 0.42), Vector3(0, 0.89, 0), Color(0.72, 0.62, 0.46))
	for off in [-0.18, -0.05, 0.10, 0.22]:
		block(waist, "Stripe", Vector3(0.043, 0.85, 0.39), Vector3(off, 0.43, 0), black)
	for side in [-1.0, 1.0]:
		var trouser := block(root, "Debit trousers", Vector3(0.33, 0.91, 0.34), Vector3(0.0, 0.70, side * 0.34), black)
		var shoe := block(root, "Giveh", Vector3(0.40, 0.18, 0.44), Vector3((0.08 if face_right else -0.08), 0.12, side * 0.34), cloth)
		var right_side: bool = (side > 0.0) if face_right else (side < 0.0)
		var side_label := "R" if right_side else "L"
		var side_color := Color(1.0, 0.18, 0.16) if right_side else Color(0.15, 0.48, 1.0)
		add_joint_debug_label(trouser, side_label, side_color, Vector3(0.0, -0.04, 0.25))
		add_joint_debug_label(shoe, side_label, side_color, Vector3(0.0, 0.23, 0.0))
	block(waist, "Head", Vector3(0.36, 0.38, 0.37), Vector3(0, 1.12, 0), skin)
	block(waist, "Hat", Vector3(0.44, 0.23, 0.44), Vector3(0, 1.40, 0), black)
	block(waist, "Nose-facing", Vector3(0.12, 0.11, 0.15), Vector3(0.22 if face_right else -0.22, 1.13, 0.06), skin)
	return root

func add_joint_debug_label(parent: Node3D, label_text: String, marker_color: Color, offset: Vector3) -> void:
	var marker := Label3D.new()
	marker.name = "DEBUG " + label_text
	marker.text = label_text
	marker.font_size = 72
	marker.pixel_size = 0.005
	marker.modulate = marker_color
	marker.outline_size = 12
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.position = offset
	parent.add_child(marker)

func add_leg_debug_marker(parent: Node3D, label_text: String, z_side: float, marker_color: Color) -> void:
	# Defender faces -X: anatomical RIGHT is -Z, LEFT is +Z.
	# Parent the marker to the fighter so it follows defender movement.
	var marker := Label3D.new()
	marker.name = "DEBUG leg " + label_text
	marker.text = label_text
	marker.font_size = 80
	marker.pixel_size = 0.005
	marker.modulate = marker_color
	marker.outline_size = 12
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.position = Vector3(-0.30, 0.68, z_side * 0.34)
	parent.add_child(marker)
	var band := block(parent, "DEBUG leg band " + label_text, Vector3(0.38, 0.09, 0.39), Vector3(0.0, 0.45, z_side * 0.34), marker_color)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func add_scenery() -> void:
	# Decorative landscape only; no collision and no change to strike physics.
	var rock := material(Color(0.48, 0.39, 0.31))
	var distant := material(Color(0.61, 0.57, 0.50))
	for i in range(9):
		var peak := MeshInstance3D.new()
		peak.name = "Zagros mountain %d" % i
		var mesh := PrismMesh.new()
		mesh.size = Vector3(3.6 + float(i % 3) * 0.7, 2.0 + float((i * 3) % 5) * 0.34, 1.6)
		peak.mesh = mesh
		peak.material_override = distant if i % 2 == 0 else rock
		peak.position = Vector3(-14.0 + float(i) * 3.5, 0.65, -8.5 - float(i % 3) * 1.5)
		add_child(peak)
	for i in range(26):
		var stone := MeshInstance3D.new()
		stone.name = "Ground pebble %d" % i
		var pebble := SphereMesh.new()
		pebble.radius = 0.09 + float(i % 4) * 0.025
		pebble.height = 0.10
		stone.mesh = pebble
		stone.material_override = rock
		stone.position = Vector3(-7.5 + float((i * 17) % 29) * 0.53, 0.015, -2.6 + float((i * 11) % 17) * 0.32)
		add_child(stone)

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.74, 0.85) # Natural daylight instead of test purple
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.83, 0.78)
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, -20)
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)
	block(self, "Ground", Vector3(17, 0.12, 7), Vector3(0, -0.08, 0), Color(0.62, 0.49, 0.32))
	add_scenery()
	attacker = person("Attacker facing RIGHT", attack_x, true)
	defender = person("Defender facing LEFT", defender_x, false)
	# Leg labels are attached directly to each moving trouser and shoe.
	terkeh = rod(self, "Terkeh attached to raised hands", STICK_RADIUS, Color(0.88, 0.69, 0.34))
	darak = rod(self, "Darak held in defender hand", GUARD_RADIUS, Color(0.36, 0.22, 0.12))
	tip_debug = MeshInstance3D.new()
	tip_debug.name = "DEBUG yellow strike tip"
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.095
	tip_mesh.height = 0.19
	tip_debug.mesh = tip_mesh
	tip_debug.material_override = material(Color(1.0, 0.90, 0.08))
	add_child(tip_debug)
	attack_hand_a = block(self, "Attacker left hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
	attack_hand_b = block(self, "Attacker right hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
	defend_hand = block(self, "Defender upper grip", Vector3(0.22, 0.20, 0.22), Vector3.ZERO, Color(0.67, 0.44, 0.29))
	defend_hand_b = block(self, "Defender lower grip", Vector3(0.22, 0.20, 0.22), Vector3.ZERO, Color(0.67, 0.44, 0.29))
	add_joint_debug_label(attack_hand_a, "L", Color(0.15, 0.48, 1.0), Vector3(0.0, 0.24, 0.0))
	add_joint_debug_label(attack_hand_b, "R", Color(1.0, 0.18, 0.16), Vector3(0.0, 0.24, 0.0))
	add_joint_debug_label(defend_hand, "R", Color(1.0, 0.18, 0.16), Vector3(0.0, 0.26, 0.0))
	add_joint_debug_label(defend_hand_b, "L", Color(0.15, 0.48, 1.0), Vector3(0.0, 0.26, 0.0))
	attack_arm_a = rod(self, "Attacker arm left", 0.095, Color(0.66, 0.44, 0.30))
	attack_arm_b = rod(self, "Attacker arm right", 0.095, Color(0.66, 0.44, 0.30))
	defend_arm = rod(self, "Defender arm", 0.11, Color(0.66, 0.44, 0.30))
	defend_arm_b = rod(self, "Defender second arm", 0.11, Color(0.66, 0.44, 0.30))
	attack_forearm_a = rod(self, "Attacker forearm near", 0.085, Color(0.66, 0.44, 0.30))
	attack_forearm_b = rod(self, "Attacker forearm far", 0.085, Color(0.66, 0.44, 0.30))
	defend_forearm_a = rod(self, "Defender forearm near", 0.095, Color(0.66, 0.44, 0.30))
	defend_forearm_b = rod(self, "Defender forearm far", 0.095, Color(0.66, 0.44, 0.30))
	attack_elbow_a = block(self, "Attacker elbow near", Vector3(0.16, 0.16, 0.16), Vector3.ZERO, Color(0.66, 0.44, 0.30))
	attack_elbow_b = block(self, "Attacker elbow far", Vector3(0.16, 0.16, 0.16), Vector3.ZERO, Color(0.66, 0.44, 0.30))
	defend_elbow_a = block(self, "Defender elbow near", Vector3(0.17, 0.17, 0.17), Vector3.ZERO, Color(0.66, 0.44, 0.30))
	defend_elbow_b = block(self, "Defender elbow far", Vector3(0.17, 0.17, 0.17), Vector3.ZERO, Color(0.66, 0.44, 0.30))
	game_camera = Camera3D.new()
	add_child(game_camera)
	game_camera.position = Vector3(0, 2.45, 12.5)
	game_camera.look_at(camera_focus, Vector3.UP)
	game_camera.fov = 53.0
	game_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 112
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	header = Label.new()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 23)
	column.add_child(header)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 19)
	column.add_child(status)
	detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	var footer := Label.new()
	footer.text = "A/D: move | TAB: switch | C: camera | W/S: darak | J/L: strike side | SPACE: swing | R: reset"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -43
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 15)
	layer.add_child(footer)
	say("Approach with D. Terkeh stays in the hands; no invisible hit line.")
	update_visuals()

func say(s: String) -> void:
	if status != null:
		status.text = s

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				shoulder_camera = not shoulder_camera
				say("Camera: behind the controlled fighter" if shoulder_camera else "Camera: original side view")
			KEY_TAB:
				defending = not defending
				swing = -1.0
				recovery = -1.0
				active_attack = false
				swing_speed = 0.0
				impact_hold = 0.0
				opponent_delay = -1.0
				# Switching control does not teleport either fighter.
				# Their current positions remain visible and controllable.
				guard_shift = 0.0
				guard_velocity = 0.0
				guard_target = 0.0
				say("DEFENSE: A/D move defender; W/S steer darak; SPACE starts opponent." if defending else "ATTACK: A/D move; J/L feint; SPACE swing.")
			KEY_R:
				defending = false
				attack_x = -2.7
				defender_x = DEF_X
				swing = -1.0
				recovery = -1.0
				active_attack = false
				swing_speed = 0.0
				impact_hold = 0.0
				opponent_delay = -1.0
				guard_shift = 0.0
				guard_velocity = 0.0
				guard_target = 0.0
				feint_depth = 0.0
				feint_target = 0.0
				score_hit = 0
				score_block = 0
				say("Reset. Move closer before striking.")
			KEY_J:
				if not defending and swing < 0.0 and recovery < 0.0:
					strike_side = 1
					feint_target = -0.60
					say("J: LEFT-hand drive -> defender RIGHT / red R leg.")
			KEY_L:
				if not defending and swing < 0.0 and recovery < 0.0:
					strike_side = -1
					feint_target = FEINT_DEPTH_LIMIT
					say("L: RIGHT-hand drive -> defender LEFT / blue L leg.")
			KEY_SPACE:
				if swing < 0.0 and recovery < 0.0 and opponent_delay < 0.0:
					if defending:
						opponent_delay = 0.55
						say("Watch the opponent. W/S moves the darak across the leg target.")
					else:
						start_swing()

func start_swing() -> void:
	swing = 0.0
	swing_speed = 0.0
	swing_finished = false
	active_attack = true
	swing_outcome = ""
	feint_target = 0.0
	say("Swing: physical terkeh sweeps toward the defender.")

func strike_ends(p: float) -> Array[Vector3]:
	# Anatomical lanes: L key/right hand -> defender L/camera (+Z).
	# J key/left hand -> defender R/far side (-Z).
	# The hand always holds the BUTT; only the opposite TIP hits.
	var t := clampf(p, 0.0, 1.0)
	var side := -float(strike_side)
	var ready_center := Vector3(attack_x + 0.56, 2.48, 0.0)
	var ready_a := ready_center + Vector3(0.0, 0.0, -STICK_LENGTH * 0.5)
	var ready_b := ready_center + Vector3(0.0, 0.0, STICK_LENGTH * 0.5)
	var ready_butt: Vector3 = ready_a if strike_side > 0 else ready_b
	var ready_tip: Vector3 = ready_b if strike_side > 0 else ready_a
	# First move the TIP into the outside lane while still near attacker.
	# This avoids cutting through the middle of the defender on the way down.
	var waypoint_butt := Vector3(attack_x + 0.24, 1.85, side * 1.18)
	var waypoint_direction := Vector3(1.42, -0.38, -side * 0.48).normalized()
	var waypoint_tip := waypoint_butt + waypoint_direction * STICK_LENGTH
	# Final: rear hand remains on the attacker's side; tip approaches
	# the OUTSIDE of the labeled leg rather than crossing the belly.
	var final_tip := Vector3(minf(defender_x - 0.08, attack_x + 2.35), 0.43, side * 0.54)
	var final_direction := Vector3(1.95, -0.66, -side * 0.23).normalized()
	var final_butt := final_tip - final_direction * STICK_LENGTH
	var butt: Vector3
	var tip: Vector3
	if t < 0.38:
		var windup := smoothstep(0.0, 0.38, t)
		butt = ready_butt.lerp(waypoint_butt, windup)
		tip = ready_tip.lerp(waypoint_tip, windup)
	else:
		var follow_through := smoothstep(0.38, 0.90, t)
		butt = waypoint_butt.lerp(final_butt, follow_through)
		tip = waypoint_tip.lerp(final_tip, follow_through)
	# Rebuild a constant-length staff from the driving-hand end.
	var axis := (tip - butt).normalized()
	tip = butt + axis * STICK_LENGTH
	var endpoints: Array[Vector3] = []
	if strike_side > 0:
		endpoints.append(butt)
		endpoints.append(tip)
	else:
		endpoints.append(tip)
		endpoints.append(butt)
	return endpoints

func strike_tip(p: float) -> Vector3:
	var ends := strike_ends(p)
	return ends[1] if strike_side > 0 else ends[0]

func guard_ends() -> Array[Vector3]:
	# One grip always follows the defender's hand. The lower end pivots across the shins.
	# Guard is held slightly ahead of the defender (toward the attacker) and camera.
	var grip := Vector3(defender_x - 0.48, 1.39, 0.18 + guard_shift * 0.20)
	var bottom := Vector3(defender_x - 0.69 + guard_shift * 0.55, 0.10, 0.18 + guard_shift * 0.62)
	var top := grip + (grip - bottom).normalized() * 0.55
	return [bottom, top]

func animate_footwork(character: Node3D, phase: float, motion: float, swing_pose: float, facing: float) -> void:
	# Small alternating steps and weight transfer, inspired by the paired dance.
	# Feet return to their original local positions when movement stops.
	var stride := minf(1.0, absf(motion) / 1.8)
	var accent := sin(swing_pose * PI) if swing_pose > 0.0 else 0.0
	var bend := smoothstep(0.02, 0.62, swing_pose) if facing > 0.0 else 0.0
	var lean := 0.36 * bend
	for child in character.get_children():
		if not child is Node3D:
			continue
		var n := child as Node3D
		if n.name == "Debit trousers" or n.name == "Giveh":
			# There are two nodes of each name; Godot auto-renames the second one.
			pass
		if n.name.begins_with("Debit trousers") or n.name.begins_with("Giveh"):
			var side := -1.0 if n.position.z < 0.0 else 1.0
			var base_x := facing * 0.08 if n.name.begins_with("Giveh") else 0.0
			var step := sin(phase + (0.0 if side < 0.0 else PI))
			n.position.x = base_x + 0.19 * stride * step + facing * 0.08 * accent
			n.position.y = (0.12 if n.name.begins_with("Giveh") else 0.70) + 0.08 * stride * maxf(0.0, step)
		elif n.name == "WaistJoint":
			# One anatomical hinge carries clothing, head and shoulders together.
			n.rotation.z = -facing * (0.05 * stride * sin(phase) + 0.88 * bend)
			n.rotation.y = float(strike_side) * 0.28 * bend if facing > 0.0 else 0.0
			n.position = Vector3(facing * 0.15 * bend, 1.14 - 0.18 * bend, 0.0)

func update_visuals() -> void:
	attacker.position.x = attack_x
	defender.position.x = defender_x
	var pose := 0.0
	if swing >= 0.0:
		pose = swing
	elif recovery >= 0.0:
		pose = lerpf(recovery_from, 0.0, smoothstep(0.0, 1.0, recovery))
	animate_footwork(attacker, attack_step_phase, attack_x - last_attack_x, pose, 1.0)
	animate_footwork(defender, defend_step_phase, defender_x - last_defender_x, 0.0, -1.0)
	var bend_amount := smoothstep(0.02, 0.62, pose)
	var shoulder_shift := Vector3(0.24 * bend_amount, -0.16 * bend_amount, 0.0)
	var ends := strike_ends(pose)
	var a := ends[0]
	var b := ends[1]
	# Ready pose uses the same 3D endpoints as the strike and collision.
	place_rod(terkeh, a, b)
	tip_debug.position = strike_tip(pose)
	# Two visible hands remain around the wooden grip and move together with it.
	var direction := (b - a).normalized()
	# In ready stance both hands hold near opposite ends of the horizontal rod.
	# During the swing the selected hand releases and returns toward the torso.
	var releasing := swing >= 0.0 or recovery >= 0.0
	var phase := swing if swing >= 0.0 else (recovery_from if recovery >= 0.0 else 0.0)
	var release_target := 0.0
	if releasing:
		release_target = smoothstep(0.0, 0.12, phase)
	if recovery >= 0.0:
		release_target *= 1.0 - smoothstep(0.45, 0.95, recovery)
	release_blend = release_target
	# The rod is ONE straight horizontal bar in the ready pose.
	# Each hand grips its OWN opposite end; never slide hands together.
	# A small inset keeps the hands visually on the wood.
	var left_grip := a + direction * 0.11
	var right_grip := b - direction * 0.11
	var left_rest := Vector3(attack_x + 0.05 + 0.10 * bend_amount, 1.28 - 0.20 * bend_amount, -0.48)
	var right_rest := Vector3(attack_x + 0.05 + 0.10 * bend_amount, 1.28 - 0.20 * bend_amount, 0.48)
	# Keep the driving hand at its assigned end; only the opposite hand releases.
	attack_hand_a.position = left_grip.lerp(left_rest, release_blend if strike_side < 0 else 0.0)
	attack_hand_b.position = right_grip.lerp(right_rest, release_blend if strike_side > 0 else 0.0)
	var left_elbow_hint: Vector3 = Vector3(1.15, -0.18, -0.48) if strike_side > 0 else Vector3(0.78, -0.32, -0.75)
	place_two_bone_arm(attack_arm_a, attack_forearm_a, attack_elbow_a, Vector3(attack_x + 0.20, 1.92, -0.14) + shoulder_shift, attack_hand_a.position, left_elbow_hint)
	var right_elbow_hint: Vector3 = Vector3(1.15, -0.18, 0.48) if strike_side < 0 else Vector3(0.78, -0.32, 0.75)
	place_two_bone_arm(attack_arm_b, attack_forearm_b, attack_elbow_b, Vector3(attack_x + 0.20, 1.92, 0.16) + shoulder_shift, attack_hand_b.position, right_elbow_hint)
	var g := guard_ends()
	place_rod(darak, g[0], g[1])
	defend_hand.position = g[0].lerp(g[1], 0.70)
	defend_hand_b.position = g[0].lerp(g[1], 0.48)
	place_two_bone_arm(defend_arm, defend_forearm_a, defend_elbow_a, Vector3(defender_x - 0.20, 1.91, 0.12), defend_hand.position, Vector3(0.65, -0.15, -0.7))
	place_two_bone_arm(defend_arm_b, defend_forearm_b, defend_elbow_b, Vector3(defender_x - 0.20, 1.91, 0.36), defend_hand_b.position, Vector3(0.65, -0.15, 0.7))

func segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var u := b - a
	var v := d - c
	var w := a - c
	var aa := u.dot(u)
	var bb := u.dot(v)
	var cc := v.dot(v)
	var dd := u.dot(w)
	var ee := v.dot(w)
	var denominator := aa * cc - bb * bb
	var s := 0.0
	var t := 0.0
	if denominator > 0.00001:
		s = clampf((bb * ee - cc * dd) / denominator, 0.0, 1.0)
	t = clampf((bb * s + ee) / maxf(cc, 0.00001), 0.0, 1.0)
	s = clampf((bb * t - dd) / maxf(aa, 0.00001), 0.0, 1.0)
	return (w + u * s - v * t).length()

func check_sweep(previous: float, current: float, previous_guard: Array[Vector3], current_guard: Array[Vector3]) -> String:
	# Adaptive swept collision: never skip a thin staff on a slow frame.
	var steps := maxi(1, ceili((current - previous) / MAX_SWEEP_STEP))
	for i in range(1, steps + 1):
		var p := lerpf(previous, current, float(i) / float(steps))
		var s := strike_ends(p)
		var alpha := float(i) / float(steps)
		var guard_a := previous_guard[0].lerp(current_guard[0], alpha)
		var guard_b := previous_guard[1].lerp(current_guard[1], alpha)
		var tip: Vector3 = s[1] if strike_side > 0 else s[0]
		# Only the forward portion can be blocked; a distant or rear section
		# touching the guard must not count as a successful defense.
		var forward_start: Vector3 = s[0].lerp(s[1], 0.76) if strike_side > 0 else s[1].lerp(s[0], 0.76)
		if segment_distance(forward_start, tip, guard_a, guard_b) <= STICK_RADIUS + GUARD_RADIUS + 0.025:
			return "block"
		# Each strike is checked only against its selected near/far leg lane.
		var target_z := -float(strike_side) * 0.34
		var leg_a := Vector3(defender_x, 0.12, target_z)
		var leg_b := Vector3(defender_x, 0.77, target_z)
		if segment_distance(tip, tip, leg_a, leg_b) <= 0.23:
			return "leg"
	return ""

func update_camera(delta: float) -> void:
	if game_camera == null:
		return
	var target_position := Vector3(0.0, 2.45, 12.5)
	var target_focus := Vector3(0.0, 1.45, 0.0)
	if shoulder_camera:
		var controlled_x := defender_x if defending else attack_x
		var opponent_x := attack_x if defending else defender_x
		var facing := -1.0 if defending else 1.0
		# Behind the controlled fighter along the attack axis, slightly offset
		# toward the viewer so the fighter and incoming stick remain visible.
		target_position = Vector3(controlled_x - facing * 3.15, 2.35, 3.65)
		target_focus = Vector3(lerpf(controlled_x, opponent_x, 0.53), 1.30, 0.0)
	var weight := 1.0 - exp(-5.5 * delta)
	game_camera.position = game_camera.position.lerp(target_position, weight)
	camera_focus = camera_focus.lerp(target_focus, weight)
	game_camera.look_at(camera_focus, Vector3.UP)

func _physics_process(delta: float) -> void:
	var previous_guard := guard_ends()
	var before_attack := attack_x
	var before_defender := defender_x
	if swing < 0.0 and recovery < 0.0 and not defending:
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			attack_x = minf(minf(MAX_X, defender_x - MIN_FIGHTER_GAP), attack_x + 2.0 * delta)
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			attack_x = maxf(MIN_X, attack_x - 2.0 * delta)
	if defending:
		# In defense mode A/D move the defender; never allow bodies to overlap.
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			defender_x = maxf(maxf(DEFENDER_MIN_X, attack_x + MIN_FIGHTER_GAP), defender_x - 1.8 * delta)
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			defender_x = minf(DEFENDER_MAX_X, defender_x + 1.8 * delta)
		if Input.is_key_pressed(KEY_W):
			guard_target = minf(0.53, guard_target + delta * 1.65)
		if Input.is_key_pressed(KEY_S):
			guard_target = maxf(-0.53, guard_target - delta * 1.65)
		# Critically damped hand-guided guard: the staff follows, never detaches.
		var omega := 9.0
		# Exact critically damped spring step for constant target; stable across frame rates.
		var error := guard_shift - guard_target
		var decay := exp(-omega * delta)
		var temp := (guard_velocity + omega * error) * delta
		guard_shift = clampf(guard_target + (error + temp) * decay, -0.53, 0.53)
		guard_velocity = (guard_velocity - omega * temp) * decay
		if opponent_delay >= 0.0:
			opponent_delay -= delta
			if opponent_delay < 0.0:
				start_swing()
	feint_depth = move_toward(feint_depth, clampf(feint_target, -FEINT_DEPTH_LIMIT, FEINT_DEPTH_LIMIT), delta * 1.7)
	if impact_hold > 0.0:
		impact_hold = maxf(0.0, impact_hold - delta)
	if recovery >= 0.0 and impact_hold <= 0.0:
		recovery += delta / RECOVERY_SECONDS
		if recovery >= 1.0:
			recovery = -1.0
	if swing >= 0.0:
		var old := swing
		# Accelerate the rod, then brake before the end of its travel.
		var stopping_distance := swing_speed * swing_speed / (2.0 * SWING_BRAKE)
		var acceleration := -SWING_BRAKE if stopping_distance >= (1.0 - swing) else SWING_ACCEL
		swing_speed = clampf(swing_speed + acceleration * delta, 0.0, SWING_MAX_SPEED)
		# Avoid a zero-speed deadlock at the end of a braked swing.
		swing = minf(1.0, swing + maxf(swing_speed, 0.30) * delta)
		var result := check_sweep(old, swing, previous_guard, guard_ends())
		if result == "block":
			score_block += 100
			say("BLOCK: terkeh touched the held darak! Defender +100")
			impact_hold = 0.22
			swing_speed = 0.0
			recovery_from = swing
			recovery = 0.0
			active_attack = false
			swing = -1.0
		elif result == "leg":
			score_hit += 100
			say("LEGAL CONTACT: terkeh reached below-knee target. Attacker +100")
			impact_hold = 0.19
			swing_speed = 0.0
			recovery_from = swing
			recovery = 0.0
			active_attack = false
			swing = -1.0
		elif swing >= 1.0:
			say("MISS: full downward arc completed; move closer to reach the leg.")
			impact_hold = 0.16
			swing_speed = 0.0
			recovery_from = 1.0
			recovery = 0.0
			active_attack = false
			swing = -1.0
	var attack_velocity := (attack_x - before_attack) / maxf(delta, 0.0001)
	var defend_velocity := (defender_x - before_defender) / maxf(delta, 0.0001)
	if absf(attack_velocity) > 0.01:
		attack_step_phase += absf(attack_velocity) * delta * 8.0
	if absf(defend_velocity) > 0.01:
		defend_step_phase += absf(defend_velocity) * delta * 8.0
	last_attack_x = attack_x - attack_velocity / 1.8
	last_defender_x = defender_x - defend_velocity / 1.8
	update_visuals()
	update_camera(delta)
	header.text = BUILD_LABEL + "  |  " + ("DEFENSE TEST" if defending else "ATTACK TEST") + "  |  Hit: %d  Block: %d" % [score_hit, score_block]
	detail.text = "Target: %s leg  |  Distance: %.2f m  |  Guard: %.2f m  |  Yellow dot = tip" % [("RIGHT / red R / J" if strike_side > 0 else "LEFT / blue L / L"), defender_x - attack_x, guard_shift]
