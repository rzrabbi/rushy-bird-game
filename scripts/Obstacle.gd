extends Spatial

var speed = 10

func _physics_process(delta):
	var current_game_speed = get_tree().current_scene.game_speed if get_tree().current_scene.get("game_speed") != null else 1.0
	global_transform.origin += delta * speed * current_game_speed * Vector3.LEFT

func _on_DestroyTimer_timeout():
	queue_free()

func _ready():
	if has_node("ScoreArea"):
		$ScoreArea.collision_mask = 3 # Detect bird on layer 1 (normal) and layer 2 (invincible/god mode)
		$ScoreArea.connect("body_entered", self, "_on_ScoreArea_body_entered")

func _on_ScoreArea_body_entered(body):
	if body.name == "Bird" and "in_score_area" in body:
		body.in_score_area = true

func _on_ScoreArea_body_exited(body):
	if body.name == "Bird":
		if "in_score_area" in body:
			body.in_score_area = false
		if not body.is_dead:
			var main_scene = get_tree().current_scene
			if main_scene.has_method("increment_score"):
				main_scene.increment_score(global_transform.origin)
