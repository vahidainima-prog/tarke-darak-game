extends Node3D

# Godot 4.x — visual mechanics test. Side camera looks along -Z.
# Feint depth: negative Z is BEHIND the attacker; positive Z is IN FRONT.
const BUILD_LABEL := "v3.7 - full downward arc"
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

func material(c: Color) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = c
 m.roughness = 0.8
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
 var cloth := Color(0.86, 0.81, 0.66)
 var black := Color(0.065, 0.07, 0.085)
 var skin := Color(0.65, 0.45, 0.32)
 block(root, "Chogha", Vector3(0.62, 0.90, 0.38), Vector3(0, 1.57, 0), cloth)
 for off in [-0.18, -0.05, 0.10, 0.22]:
  block(root, "Stripe", Vector3(0.043, 0.85, 0.39), Vector3(off, 1.57, 0), black)
 for side in [-1.0, 1.0]:
  block(root, "Debit trousers", Vector3(0.33, 0.91, 0.43), Vector3(side * 0.18, 0.70, 0), black)
  block(root, "Giveh", Vector3(0.40, 0.18, 0.52), Vector3(side * 0.18 + (0.08 if face_right else -0.08), 0.12, 0.09), cloth)
 block(root, "Head", Vector3(0.36, 0.38, 0.37), Vector3(0, 2.26, 0), skin)
 block(root, "Hat", Vector3(0.44, 0.23, 0.44), Vector3(0, 2.54, 0), black)
 block(root, "Nose-facing", Vector3(0.12, 0.11, 0.15), Vector3(0.22 if face_right else -0.22, 2.27, 0.06), skin)
 return root

func _ready() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.48, 0.27, 0.64) # V3 connection test: unmistakable purple sky
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.85, 0.88, 0.9)
 world.environment = env
 add_child(world)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55, -30, -20)
 light.light_energy = 1.6
 add_child(light)
 block(self, "Ground", Vector3(17, 0.12, 7), Vector3(0, -0.08, 0), Color(0.32, 0.51, 0.28))
 attacker = person("Attacker facing RIGHT", attack_x, true)
 defender = person("Defender facing LEFT", defender_x, false)
 terkeh = rod(self, "Terkeh attached to raised hands", STICK_RADIUS, Color(0.93, 0.61, 0.20))
 darak = rod(self, "Darak held in defender hand", GUARD_RADIUS, Color(0.27, 0.14, 0.07))
 attack_hand_a = block(self, "Attacker left hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 attack_hand_b = block(self, "Attacker right hand", Vector3(0.19, 0.17, 0.17), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 defend_hand = block(self, "Defender upper grip", Vector3(0.22, 0.20, 0.22), Vector3.ZERO, Color(0.67, 0.44, 0.29))
 defend_hand_b = block(self, "Defender lower grip", Vector3(0.22, 0.20, 0.22), Vector3.ZERO, Color(0.67, 0.44, 0.29))
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
 var cam := Camera3D.new()
 add_child(cam)
 cam.position = Vector3(0, 2.45, 12.5)
 cam.look_at(Vector3(0, 1.45, 0), Vector3.UP)
 cam.fov = 53.0
 cam.current = true
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
 footer.text = "A/D: move | TAB: switch | W/S: darak | J: left strike | L: right strike | SPACE: swing | R: reset"
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
     say("LEFT attack selected: right hand releases during swing.")
   KEY_L:
    if not defending and swing < 0.0 and recovery < 0.0:
     strike_side = -1
     feint_target = FEINT_DEPTH_LIMIT
     say("RIGHT attack selected: left hand releases during swing.")
   KEY_SPACE:
    if swing < 0.0 and recovery < 0.0 and opponent_delay < 0.0:
     if defending:
      opponent_delay = 0.55
      say("Watch the opponent. W/S shifts the held darak.")
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
 # Kinematic, constrained two-handed strike. The grip is always at the hands.
 # Acceleration and deceleration make the swing read as a weighted wooden rod.
 var t := clampf(p, 0.0, 1.0)
 # Phase is integrated with angular acceleration and braking, not eased by time.
 # A full follow-through: the tip travels forward and down toward the shins.
 # Lateral depth passes through the guard plane before the leg plane.
 var angle := lerpf(0.0, -1.35, smoothstep(0.0, 1.0, t))
 var z := lerpf(-0.46 + feint_depth * 0.25, 0.38, smoothstep(0.0, 0.65, t))
 z = lerpf(z, 0.05, smoothstep(0.65, 1.0, t))
 # The rod extends on BOTH sides of the two-handed grip, rather than
 # pointing out from a single hand. This keeps the ready pose horizontal.
 # The holding hand drives the rod forward; the tip drops to shin height.
 var grip_center := Vector3(attack_x + 0.05 + 1.27 * t, 2.57 - 1.26 * t, z)
 var direction := Vector3(cos(angle), sin(angle), 0.0)
 var butt := grip_center - direction * (STICK_LENGTH * 0.5)
 var tip := grip_center + direction * (STICK_LENGTH * 0.5)
 return [butt, tip]

func guard_ends() -> Array[Vector3]:
 # One grip always follows the defender's hand. The lower end pivots across the shins.
 # Guard is held slightly ahead of the defender (toward the attacker) and camera.
 var grip := Vector3(defender_x - 0.48, 1.39, 0.48)
 var bottom := Vector3(defender_x - 0.69 + guard_shift, 0.10, 0.48)
 var top := grip + (grip - bottom).normalized() * 0.55
 return [bottom, top]

func update_visuals() -> void:
 attacker.position.x = attack_x
 defender.position.x = defender_x
 var pose := 0.0
 if swing >= 0.0:
  pose = swing
 elif recovery >= 0.0:
  pose = lerpf(recovery_from, 0.0, smoothstep(0.0, 1.0, recovery))
 var ends := strike_ends(pose)
 var a := ends[0]
 var b := ends[1]
 # Ready pose uses the same 3D endpoints as the strike and collision.
 place_rod(terkeh, a, b)
 # Two visible hands remain around the wooden grip and move together with it.
 var direction := (b - a).normalized()
 # In ready stance both hands hold near opposite ends of the horizontal rod.
 # During the swing the selected hand releases and returns toward the torso.
 var releasing := swing >= 0.0 or recovery >= 0.0
 var phase := swing if swing >= 0.0 else (recovery_from if recovery >= 0.0 else 0.0)
 var release_target := 0.0
 if releasing:
  release_target = smoothstep(0.05, 0.34, phase)
 if recovery >= 0.0:
  release_target *= 1.0 - smoothstep(0.20, 0.95, recovery)
 release_blend = release_target
 var left_grip := a + direction * 0.12
 var right_grip := b - direction * 0.12
 var left_rest := Vector3(attack_x - 0.30, 1.86, 0.25)
 var right_rest := Vector3(attack_x + 0.33, 1.88, 0.25)
 attack_hand_a.position = left_grip.lerp(left_rest, release_blend if strike_side < 0 else 0.0)
 attack_hand_b.position = right_grip.lerp(right_rest, release_blend if strike_side > 0 else 0.0)
 place_two_bone_arm(attack_arm_a, attack_forearm_a, attack_elbow_a, Vector3(attack_x + 0.20, 1.92, -0.14), attack_hand_a.position, Vector3(-0.6, 0.1, -0.7))
 place_two_bone_arm(attack_arm_b, attack_forearm_b, attack_elbow_b, Vector3(attack_x + 0.20, 1.92, 0.16), attack_hand_b.position, Vector3(-0.6, 0.1, 0.7))
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
  if segment_distance(s[0], s[1], guard_a, guard_b) <= STICK_RADIUS + GUARD_RADIUS + 0.025:
   return "block"
  for foot_x in [defender_x - 0.18, defender_x + 0.18]:
   var leg_a := Vector3(foot_x, 0.12, 0.0)
   var leg_b := Vector3(foot_x, 0.77, 0.0)
   if segment_distance(s[0], s[1], leg_a, leg_b) <= 0.20:
    return "leg"
 return ""

func _physics_process(delta: float) -> void:
 var previous_guard := guard_ends()
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
 update_visuals()
 header.text = BUILD_LABEL + "  |  " + ("DEFENSE TEST" if defending else "ATTACK TEST") + "  |  Hit: %d  Block: %d" % [score_hit, score_block]
 detail.text = "Distance: %.2f m   |   Darak offset: %.2f m   |   A/D: move  |  SPACE: strike" % [defender_x - attack_x, guard_shift]
