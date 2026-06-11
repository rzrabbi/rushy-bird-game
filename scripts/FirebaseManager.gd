extends Node

var config_file_path = "res://secret_config.cfg"
var user_id = ""
var is_logged_in = false

signal leaderboard_updated(all_time, seasonal)
signal auth_state_changed(is_logged_in)
signal stats_sync_finished(success, timestamp)

# Profile Claim Signals
signal profile_claim_succeeded(cloud_stats)
signal profile_claim_failed(reason)
signal profile_claim_conflict(guest_stats, cloud_stats)
signal cleanup_completed
signal migration_completed
signal upsert_completed
signal delete_completed
signal score_sync_finished(success)

var _last_upsert_success = false
var _last_delete_success = false
var last_refresh_time = 0
signal token_refresh_done(success)


enum AuthStates {
	ANONYMOUS_SESSION,
	LINKING_IN_PROGRESS,
	LINK_SUCCESS,
	LINK_CONFLICT,
	FETCHING_CLOUD_DATA,
	CONFLICT_RESOLUTION_WAITING,
	OVERWRITE_CLOUD,
	DISCARD_GUEST,
	CANCELLING
}
var current_auth_state: int = AuthStates.ANONYMOUS_SESSION

# Caching for Migration
var cached_guest_auth = {}
var cached_guest_stats = {}
var cached_guest_hiscores = {}
var cached_guest_highest_levels = {}
var cached_guest_name = ""
var target_cloud_uid = ""
var cached_cloud_stats = {}

# Caching for Google link
var _cached_link_stats = {}
var _cached_link_hiscores = {}
var _cached_link_highest_levels = {}
var _cached_link_name = ""
var js_callback = null

var is_config_available = false

func _ready():
	var env = ConfigFile.new()
	var err = env.load("res://secret_config.cfg")
	is_config_available = (err == OK)
	if not is_config_available:
		printerr("[Firebase Error] >> secret_config.cfg file is missing. Leaderboard is disabled on this build.")
		return
	_setup_auth()
	Firebase.Firestore.connect("error", self, "_on_firestore_error")
	
	if OS.has_feature("JavaScript"):
		JavaScript.eval("""
			window._get_auth_event_data = function(data) {
				if (data && typeof data === 'object') {
					return [data.type, data.token];
				}
				return [null, null];
			};
		""")
		js_callback = JavaScript.create_callback(self, "_on_js_message")
		var window = JavaScript.get_interface("window")
		if window:
			window.addEventListener("message", js_callback)

func _setup_auth():
	Firebase.Auth.connect("login_succeeded", self, "_on_login_succeeded")
	Firebase.Auth.connect("signup_succeeded", self, "_on_signup_succeeded")
	Firebase.Auth.connect("token_refresh_succeeded", self, "_on_token_refresh_succeeded")
	Firebase.Auth.connect("logged_out", self, "_on_logged_out")
	Firebase.Auth.connect("login_failed", self, "_on_login_failed")
	Firebase.Auth.connect("signup_failed", self, "_on_signup_failed")
	
	# Check if user is already logged in
	var dir = Directory.new()
	if dir.file_exists("user://user.auth"):
		Firebase.Auth.check_auth_file()
	else:
		print("No auth file found, logging in anonymously...")
		Firebase.Auth.login_anonymous()

func _on_login_succeeded(auth_result):
	last_refresh_time = OS.get_unix_time()
	emit_signal("token_refresh_done", true)
	if current_auth_state == AuthStates.FETCHING_CLOUD_DATA:
		# We successfully signed into the permanent account to fetch stats
		target_cloud_uid = auth_result.localid
		_set_active_auth(auth_result)
		Firebase.Auth.save_auth(auth_result)
		_fetch_cloud_stats_for_conflict()
		return

	if current_auth_state == AuthStates.LINKING_IN_PROGRESS:
		# On HTML5, if linking was a success it would go here (unless it was a signup).
		# But on desktop/editor, get_auth_localhost() directly logs in.
		# If we are NOT running HTML5 (i.e. we are on desktop/editor),
		# we need to treat this direct login as a potential conflict and fetch cloud stats.
		if OS.get_name() != "HTML5":
			target_cloud_uid = auth_result.localid
			Firebase.Auth.save_auth(auth_result)
			current_auth_state = AuthStates.FETCHING_CLOUD_DATA
			_fetch_cloud_stats_for_conflict()
			return
			
		var guest_uid = cached_guest_auth.get("localid", "") if not cached_guest_auth.empty() else ""
		current_auth_state = AuthStates.LINK_SUCCESS
		user_id = auth_result.localid
		is_logged_in = true
		Firebase.Auth.save_auth(auth_result)
		emit_signal("auth_state_changed", true)
		if guest_uid != "" and guest_uid != user_id:
			_migrate_guest_data_to_new_user(guest_uid)
			yield(self, "migration_completed")
		current_auth_state = AuthStates.ANONYMOUS_SESSION # Reset to idle
		emit_signal("profile_claim_succeeded", {})
		return

	var prev_user_id = user_id
	user_id = auth_result.localid
	var was_logged_in = is_logged_in
	is_logged_in = true
	Firebase.Auth.save_auth(auth_result)
	print("User Logged In: ", user_id)
	if not was_logged_in or user_id != prev_user_id:
		emit_signal("auth_state_changed", true)

func _on_signup_succeeded(auth_result):
	last_refresh_time = OS.get_unix_time()
	emit_signal("token_refresh_done", true)
	if current_auth_state == AuthStates.LINKING_IN_PROGRESS:
		var guest_uid = cached_guest_auth.get("localid", "") if not cached_guest_auth.empty() else ""
		current_auth_state = AuthStates.LINK_SUCCESS
		var prev_user_id = user_id
		user_id = auth_result.localid
		var was_logged_in = is_logged_in
		is_logged_in = true
		Firebase.Auth.save_auth(auth_result)
		if not was_logged_in or user_id != prev_user_id:
			emit_signal("auth_state_changed", true)
		if guest_uid != "" and guest_uid != user_id:
			_migrate_guest_data_to_new_user(guest_uid)
			yield(self, "migration_completed")
		current_auth_state = AuthStates.ANONYMOUS_SESSION
		emit_signal("profile_claim_succeeded", {})
		return
	_on_login_succeeded(auth_result)

func _on_token_refresh_succeeded(auth_result):
	last_refresh_time = OS.get_unix_time()
	var prev_user_id = user_id
	user_id = auth_result.localid
	var was_logged_in = is_logged_in
	is_logged_in = true
	Firebase.Auth.save_auth(auth_result)
	print("Token Refreshed: ", user_id)
	emit_signal("token_refresh_done", true)
	if not was_logged_in or user_id != prev_user_id:
		emit_signal("auth_state_changed", true)

func _on_login_failed(code, message):
	emit_signal("token_refresh_done", false)
	if current_auth_state == AuthStates.LINKING_IN_PROGRESS:
		_handle_linking_conflict(code, message)
		return

	if current_auth_state == AuthStates.FETCHING_CLOUD_DATA:
		# Login failed during fallback. Restore cached guest session to prevent local data loss.
		current_auth_state = AuthStates.CANCELLING
		if not cached_guest_auth.empty():
			Firebase.Auth.save_auth(cached_guest_auth)
			Firebase.Auth.auth = cached_guest_auth
			user_id = cached_guest_auth.localid
			is_logged_in = true
			emit_signal("auth_state_changed", true)
		current_auth_state = AuthStates.ANONYMOUS_SESSION
		emit_signal("profile_claim_failed", "Login failed: " + str(message))
		return

	print("Firebase Auth login/refresh failed: ", code, " - ", message, ". Logging in anonymously...")
	Firebase.Auth.login_anonymous()

func _on_signup_failed(code, message):
	emit_signal("token_refresh_done", false)
	if current_auth_state == AuthStates.LINKING_IN_PROGRESS:
		_handle_linking_conflict(code, message)
		return
	print("Firebase Auth signup failed: ", code, " - ", message)

func _on_logged_out():
	user_id = ""
	is_logged_in = false
	emit_signal("auth_state_changed", false)
	print("User Logged Out")

func get_current_user_id() -> String:
	if is_logged_in and user_id != "":
		return user_id
	return ""

func is_claiming_profile() -> bool:
	return current_auth_state != AuthStates.ANONYMOUS_SESSION

func submit_score(score: int, mode: int, player_name: String, force_overwrite: bool = false):
	if mode != 1:
		print("[FirebaseManager] Skipping leaderboard submission for non-escalation mode: ", mode)
		emit_signal("score_sync_finished", true)
		return

	if not is_config_available:
		emit_signal("score_sync_finished", false)
		return
		
	var uid = get_current_user_id()
	if uid == "":
		emit_signal("score_sync_finished", false)
		return
		
	var all_time_collection = Firebase.Firestore.collection("leaderboard_rushybird_alltime")
	var seasonal_collection = Firebase.Firestore.collection("leaderboard_rushybird_seasonal")
	var is_registered = false
	if is_logged_in and Firebase.Auth.auth:
		var email = Firebase.Auth.auth.get("email", "")
		if email != "":
			is_registered = true
			
	var data = {
		"uid": uid,
		"score": score,
		"player_name": player_name,
		"timestamp": OS.get_unix_time(),
		"is_registered": is_registered
	}
	
	var time_dict = OS.get_datetime()
	var period_str = str(time_dict.year) + "-" + str(time_dict.month).pad_zeros(2)
	var seasonal_data = data.duplicate()
	seasonal_data["period"] = period_str
	
	_upsert_doc(all_time_collection, uid, data, force_overwrite)
	yield(self, "upsert_completed")
	var success1 = _last_upsert_success
	
	_upsert_doc(seasonal_collection, uid, seasonal_data, force_overwrite)
	yield(self, "upsert_completed")
	var success2 = _last_upsert_success
	
	emit_signal("score_sync_finished", success1 and success2)

func _upsert_doc(collection, uid, data, force_overwrite: bool = false):
	var doc = yield(collection.get_doc(uid), "completed")
	var result = null
	if doc != null:
		if not force_overwrite and collection.collection_name in ["leaderboard_rushybird_alltime", "leaderboard_rushybird_seasonal"]:
			var new_score = int(data.get("score", 0))
			var existing_score = 0
			var score_val = doc.get_value("score")
			if score_val != null:
				existing_score = int(score_val)
			if new_score <= existing_score:
				var existing_name = doc.get_value("player_name")
				var new_name = data.get("player_name", "")
				if new_name != "" and existing_name != new_name:
					print("[Firebase] Score is not higher, but player name changed from '", existing_name, "' to '", new_name, "'. Updating name on leaderboard.")
					doc.add_or_update_field("player_name", new_name)
					doc.add_or_update_field("timestamp", OS.get_unix_time())
					if data.has("is_registered"):
						doc.add_or_update_field("is_registered", data.get("is_registered"))
					result = yield(collection.update(doc), "completed")
					_last_upsert_success = (result != null)
					emit_signal("upsert_completed")
					return
				else:
					print("[Firebase] Score is not higher and name is same. Skipping update.")
					_last_upsert_success = true
					emit_signal("upsert_completed")
					return
		
		for k in data:
			doc.add_or_update_field(k, data[k])
		result = yield(collection.update(doc), "completed")
	else:
		result = yield(collection.add(uid, data), "completed")
	_last_upsert_success = (result != null)
	emit_signal("upsert_completed")
	
func fetch_leaderboards():
	if not is_config_available:
		emit_signal("leaderboard_updated", null, null)
		return
		
	# Firestore query
	var all_time_query = FirestoreQuery.new()
	all_time_query.from("leaderboard_rushybird_alltime", false)
	all_time_query.order_by("score", FirestoreQuery.DIRECTION.DESCENDING)
	all_time_query.limit(50)
	
	var all_time_result = yield(Firebase.Firestore.query(all_time_query), "completed")
	_on_all_time_result(all_time_result)
	
	var time_dict = OS.get_datetime()
	var period_str = str(time_dict.year) + "-" + str(time_dict.month).pad_zeros(2)
	
	var seasonal_query = FirestoreQuery.new()
	seasonal_query.from("leaderboard_rushybird_seasonal", false)
	seasonal_query.where("period", FirestoreQuery.OPERATOR.EQUAL, period_str)
	seasonal_query.order_by("score", FirestoreQuery.DIRECTION.DESCENDING)
	seasonal_query.limit(50)
	
	var seasonal_result = yield(Firebase.Firestore.query(seasonal_query), "completed")
	_on_seasonal_result(seasonal_result)

var _temp_all_time = []
var _temp_seasonal = []

func _on_all_time_result(result):
	_temp_all_time = []
	if result != null and typeof(result) == TYPE_ARRAY:
		for doc in result:
			if typeof(doc) != TYPE_OBJECT or not doc.has_method("keys"):
				print("WARNING: doc is not a valid FirestoreDocument! Type: ", typeof(doc), " Value: ", doc)
				continue
			var dict = {}
			dict["uid"] = doc.doc_name
			for key in doc.keys():
				dict[key] = doc.get_value(key)
			_temp_all_time.append(dict)
	_check_leaderboard_complete()

func _on_seasonal_result(result):
	_temp_seasonal = []
	if result != null and typeof(result) == TYPE_ARRAY:
		for doc in result:
			if typeof(doc) != TYPE_OBJECT or not doc.has_method("keys"):
				print("WARNING: doc is not a valid FirestoreDocument! Type: ", typeof(doc), " Value: ", doc)
				continue
			var dict = {}
			dict["uid"] = doc.doc_name
			for key in doc.keys():
				dict[key] = doc.get_value(key)
			_temp_seasonal.append(dict)
	_check_leaderboard_complete()

func _check_leaderboard_complete():
	emit_signal("leaderboard_updated", _temp_all_time, _temp_seasonal)

func _on_query_error(code, status, message):
	print("Firestore Query Error: ", code, status, message)

func submit_stats(stats: Dictionary, hiscores: Dictionary, highest_levels: Dictionary, player_name: String):
	if not is_config_available:
		emit_signal("stats_sync_finished", false, 0)
		return
		
	var uid = get_current_user_id()
	if uid == "":
		emit_signal("stats_sync_finished", false, 0)
		return
		
	var stats_collection = Firebase.Firestore.collection("rushybird_player_stats")
	
	var data = {
		"uid": uid,
		"player_name": player_name,
		"classic_highscore": int(hiscores.get(0, 0)),
		"escalation_highscore": int(hiscores.get(1, 0)),
		"escalation_highest_level": int(highest_levels.get(1, 1)),
		"total_games": int(stats.get("total_games", 0)),
		"playtime": float(stats.get("playtime", 0.0)),
		"total_deaths": int(stats.get("total_deaths", 0)),
		"total_revives": int(stats.get("total_revives", 0)),
		"total_distance": float(stats.get("total_distance", 0.0)),
		"last_updated": int(OS.get_unix_time())
	}
	
	_upsert_doc(stats_collection, uid, data)
	yield(self, "upsert_completed")
	var success = _last_upsert_success
	emit_signal("stats_sync_finished", success, data["last_updated"] if success else 0)
# --- Profile Linking & Conflict Handling ---

var _cached_link_email = ""
var _cached_link_password = ""
var _cached_link_oauth_token = ""
var _cached_link_oauth_provider = null

func start_profile_claim_email(email: String, password: String, stats: Dictionary, hiscores: Dictionary, highest_levels: Dictionary, p_name: String):
	if Firebase.Auth.auth == null or not Firebase.Auth.auth.has("idtoken"):
		emit_signal("profile_claim_failed", "Not authenticated as guest.")
		return
		
	# Check if token is expired or close to it
	if OS.get_unix_time() - last_refresh_time > 3000:
		print("[Firebase] Token expired or close to expiry. Refreshing before link...")
		Firebase.Auth.manual_token_refresh(Firebase.Auth.auth)
		var success = yield(self, "token_refresh_done")
		if not success:
			emit_signal("profile_claim_failed", "Failed to refresh expired guest token.")
			return

	current_auth_state = AuthStates.LINKING_IN_PROGRESS
	
	cached_guest_auth = Firebase.Auth.auth.duplicate()
	cached_guest_stats = stats.duplicate()
	cached_guest_hiscores = hiscores.duplicate()
	cached_guest_highest_levels = highest_levels.duplicate()
	cached_guest_name = p_name
	
	_cached_link_email = email
	_cached_link_password = password
	_cached_link_oauth_token = ""
	
	Firebase.Auth.link_with_email_and_password(cached_guest_auth.idtoken, email, password)

func start_profile_claim_oauth(token: String, provider, stats: Dictionary, hiscores: Dictionary, highest_levels: Dictionary, p_name: String):
	if Firebase.Auth.auth == null or not Firebase.Auth.auth.has("idtoken"):
		emit_signal("profile_claim_failed", "Not authenticated as guest.")
		return
		
	# Check if token is expired or close to it
	if OS.get_unix_time() - last_refresh_time > 3000:
		print("[Firebase] Token expired or close to expiry. Refreshing before link...")
		Firebase.Auth.manual_token_refresh(Firebase.Auth.auth)
		var success = yield(self, "token_refresh_done")
		if not success:
			emit_signal("profile_claim_failed", "Failed to refresh expired guest token.")
			return

	current_auth_state = AuthStates.LINKING_IN_PROGRESS
	
	cached_guest_auth = Firebase.Auth.auth.duplicate()
	cached_guest_stats = stats.duplicate()
	cached_guest_hiscores = hiscores.duplicate()
	cached_guest_highest_levels = highest_levels.duplicate()
	cached_guest_name = p_name
	
	_cached_link_email = ""
	_cached_link_password = ""
	_cached_link_oauth_token = token
	_cached_link_oauth_provider = provider
	
	Firebase.Auth.link_with_oauth(cached_guest_auth.idtoken, token, provider)

func _handle_linking_conflict(code, message):
	if str(code) == "400" and ("EMAIL_EXISTS" in message or "CREDENTIAL_ALREADY_IN_USE" in message or "FEDERATED_SIGNIN_ADVERSARY_USER" in message or "CREDENTIAL_TOO_OLD_LOGIN_AGAIN" in message):
		current_auth_state = AuthStates.FETCHING_CLOUD_DATA
		if _cached_link_email != "":
			Firebase.Auth.login_with_email_and_password(_cached_link_email, _cached_link_password)
		elif _cached_link_oauth_token != "":
			Firebase.Auth.login_with_oauth(_cached_link_oauth_token, _cached_link_oauth_provider)
	else:
		current_auth_state = AuthStates.ANONYMOUS_SESSION
		emit_signal("profile_claim_failed", message)

func _fetch_cloud_stats_for_conflict():
	print("[FirebaseManager] Fetching cloud stats for conflict detection for UID: ", target_cloud_uid)
	var collection = Firebase.Firestore.collection("rushybird_player_stats")
	var doc = yield(collection.get_doc(target_cloud_uid), "completed")
	cached_cloud_stats = {}
	if doc != null and typeof(doc) == TYPE_OBJECT and doc.has_method("get_value"):
		print("[FirebaseManager] Cloud stats doc found in Firestore.")
		var p_name = doc.get_value("player_name")
		var classic_hs = doc.get_value("classic_highscore")
		var escalation_hs = doc.get_value("escalation_highscore")
		var escalation_hl = doc.get_value("escalation_highest_level")
		var games = doc.get_value("total_games")
		var deaths = doc.get_value("total_deaths")
		var revives = doc.get_value("total_revives")
		var dist = doc.get_value("total_distance")
		var play = doc.get_value("playtime")
		
		cached_cloud_stats = {
			"player_name": str(p_name) if p_name != null else "",
			"classic_highscore": int(classic_hs) if classic_hs != null else 0,
			"escalation_highscore": int(escalation_hs) if escalation_hs != null else 0,
			"escalation_highest_level": int(escalation_hl) if escalation_hl != null else 1,
			"total_games": int(games) if games != null else 0,
			"total_deaths": int(deaths) if deaths != null else 0,
			"total_revives": int(revives) if revives != null else 0,
			"total_distance": float(dist) if dist != null else 0.0,
			"playtime": float(play) if play != null else 0.0
		}
		print("[FirebaseManager] Parsed cloud stats: ", cached_cloud_stats)
	else:
		print("[FirebaseManager] No cloud stats doc found or document type invalid. doc = ", doc)
		cached_cloud_stats = {
			"player_name": "",
			"classic_highscore": 0, "escalation_highscore": 0, "escalation_highest_level": 1,
			"total_games": 0, "total_deaths": 0, "total_revives": 0, "total_distance": 0.0, "playtime": 0.0
		}
	var has_cloud_stats = cached_cloud_stats.get("classic_highscore", 0) > 0 or cached_cloud_stats.get("escalation_highscore", 0) > 0 or cached_cloud_stats.get("total_games", 0) > 0
	print("[FirebaseManager] has_cloud_stats = ", has_cloud_stats)
	if has_cloud_stats:
		print("[FirebaseManager] Profile conflict exists! Emitting profile_claim_conflict...")
		current_auth_state = AuthStates.CONFLICT_RESOLUTION_WAITING
		emit_signal("profile_claim_conflict", cached_guest_stats, cached_cloud_stats)
	else:
		print("[FirebaseManager] No conflict. Auto-overwriting cloud stats.")
		resolve_conflict_overwrite_cloud()

func resolve_conflict_overwrite_cloud():
	var guest_uid = cached_guest_auth.get("localid", "") if not cached_guest_auth.empty() else ""
	current_auth_state = AuthStates.OVERWRITE_CLOUD
	user_id = target_cloud_uid
	is_logged_in = true
	emit_signal("auth_state_changed", true)
	
	submit_stats(cached_guest_stats, cached_guest_hiscores, cached_guest_highest_levels, cached_guest_name)
	yield(self, "stats_sync_finished")
	
	# Delete existing cloud leaderboard entries to permit overwriting with lower score (bypasses update rule via create)
	var alltime_col = Firebase.Firestore.collection("leaderboard_rushybird_alltime")
	_delete_doc(alltime_col, user_id)
	yield(self, "delete_completed")
	
	var seasonal_col = Firebase.Firestore.collection("leaderboard_rushybird_seasonal")
	_delete_doc(seasonal_col, user_id)
	yield(self, "delete_completed")
	
	var score = cached_guest_hiscores.get(1, 0)
	if score > 0: 
		submit_score(score, 1, cached_guest_name, true)
		yield(self, "score_sync_finished")
		
	if guest_uid != "" and guest_uid != user_id:
		_clean_abandoned_guest(guest_uid)
		yield(self, "cleanup_completed")
			
	current_auth_state = AuthStates.ANONYMOUS_SESSION
	emit_signal("profile_claim_succeeded", {})

func resolve_conflict_discard_guest():
	var guest_uid = cached_guest_auth.get("localid", "") if not cached_guest_auth.empty() else ""
	current_auth_state = AuthStates.DISCARD_GUEST
	user_id = target_cloud_uid
	is_logged_in = true
	emit_signal("auth_state_changed", true)
	if guest_uid != "" and guest_uid != user_id:
		_clean_abandoned_guest(guest_uid)
		yield(self, "cleanup_completed")
			
	current_auth_state = AuthStates.ANONYMOUS_SESSION
	emit_signal("profile_claim_succeeded", cached_cloud_stats)

func resolve_conflict_cancel():
	current_auth_state = AuthStates.CANCELLING
	Firebase.Auth.logout()
	_set_active_auth(cached_guest_auth)
	Firebase.Auth.save_auth(cached_guest_auth)
	user_id = cached_guest_auth.localid
	is_logged_in = true
	emit_signal("auth_state_changed", true)
	current_auth_state = AuthStates.ANONYMOUS_SESSION

func _set_active_auth(auth_dict: Dictionary):
	Firebase.Auth.auth = auth_dict
	Firebase.Firestore.auth = auth_dict
	for coll in Firebase.Firestore.get_children():
		if coll is FirestoreCollection:
			coll.auth = auth_dict

func _delete_doc(collection, doc_name):
	var doc = FirestoreDocument.new()
	doc.doc_name = doc_name
	doc.collection_name = collection.collection_name
	var success = yield(collection.delete(doc), "completed")
	_last_delete_success = success
	emit_signal("delete_completed")

func _clean_abandoned_guest(guest_uid: String):
	if guest_uid == "" or cached_guest_auth.empty():
		emit_signal("cleanup_completed")
		return
	print("[Firebase] Cleaning up abandoned guest UID: ", guest_uid)
	
	var permanent_auth = Firebase.Auth.auth.duplicate()
	_set_active_auth(cached_guest_auth)
	
	var alltime_col = Firebase.Firestore.collection("leaderboard_rushybird_alltime")
	_delete_doc(alltime_col, guest_uid)
	yield(self, "delete_completed")
	
	var seasonal_col = Firebase.Firestore.collection("leaderboard_rushybird_seasonal")
	_delete_doc(seasonal_col, guest_uid)
	yield(self, "delete_completed")
	
	var stats_col = Firebase.Firestore.collection("rushybird_player_stats")
	_delete_doc(stats_col, guest_uid)
	yield(self, "delete_completed")
	
	_set_active_auth(permanent_auth)
	print("[Firebase] Clean up complete for guest UID: ", guest_uid)
	emit_signal("cleanup_completed")

func _migrate_guest_data_to_new_user(guest_uid: String):
	print("[Firebase] Migrating guest data to new user ID: ", user_id)
	
	submit_stats(cached_guest_stats, cached_guest_hiscores, cached_guest_highest_levels, cached_guest_name)
	yield(self, "stats_sync_finished")
	
	var score = cached_guest_hiscores.get(1, 0)
	if score > 0: 
		submit_score(score, 1, cached_guest_name)
		yield(self, "score_sync_finished")
			
	_clean_abandoned_guest(guest_uid)
	yield(self, "cleanup_completed")
	emit_signal("migration_completed")

func _on_js_message(args):
	var event = args[0]
	if event:
		var data = event.data
		if data:
			var window = JavaScript.get_interface("window")
			var extracted = window._get_auth_event_data(data)
			if extracted and extracted[0] == "google_auth_token":
				var token = extracted[1]
				_on_google_code_received(token)

func start_google_login(stats: Dictionary, hiscores: Dictionary, highest_levels: Dictionary, p_name: String):
	_cached_link_stats = stats.duplicate()
	_cached_link_hiscores = hiscores.duplicate()
	_cached_link_highest_levels = highest_levels.duplicate()
	_cached_link_name = p_name
	
	cached_guest_stats = stats.duplicate()
	cached_guest_hiscores = hiscores.duplicate()
	cached_guest_highest_levels = highest_levels.duplicate()
	cached_guest_name = p_name
	
	if Firebase.Auth.auth != null:
		cached_guest_auth = Firebase.Auth.auth.duplicate()
		
	current_auth_state = AuthStates.LINKING_IN_PROGRESS
	
	var client_id = Firebase.Auth._config.clientId
	var redirect_uri = "https://" + Firebase.Auth._config.projectId + ".firebaseapp.com/auth.html"
	
	if OS.has_feature("JavaScript"):
		var url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=" + client_id + "&redirect_uri=" + redirect_uri + "&response_type=code&scope=email%20openid%20profile"
		JavaScript.eval("window.open('" + url + "', 'Google Sign-In', 'width=500,height=600');")
	else:
		Firebase.Auth.set_redirect_uri("http://localhost:8060/")
		Firebase.Auth.get_auth_localhost()

func _on_google_code_received(code: String):
	var redirect_uri = "https://" + Firebase.Auth._config.projectId + ".firebaseapp.com/auth.html"
	Firebase.Auth.set_redirect_uri(redirect_uri)
	
	var provider = Firebase.Auth.get_GoogleProvider()
	
	var email = ""
	if Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
		
	if is_logged_in and email == "":
		current_auth_state = AuthStates.LINKING_IN_PROGRESS
		cached_guest_auth = Firebase.Auth.auth.duplicate()
		cached_guest_stats = _cached_link_stats.duplicate()
		cached_guest_hiscores = _cached_link_hiscores.duplicate()
		cached_guest_highest_levels = _cached_link_highest_levels.duplicate()
		cached_guest_name = _cached_link_name
		
		_cached_link_email = ""
		_cached_link_password = ""
		_cached_link_oauth_token = code
		_cached_link_oauth_provider = provider
		
		Firebase.Auth.link_with_oauth(cached_guest_auth.idtoken, code, provider)
	else:
		Firebase.Auth.login_with_oauth(code, provider)

func _on_firestore_error(error_dict):
	print("[Firebase Firestore Error] ", error_dict)
