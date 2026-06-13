extends Node

var config_file_path = "res://addons/godot-firebase/.env"
var user_id = ""
var is_logged_in = false

signal leaderboard_updated(all_time, seasonal)
signal auth_state_changed(is_logged_in)
signal stats_sync_finished(success, timestamp)

signal profile_claim_succeeded(cloud_stats)
signal profile_claim_failed(reason)
signal profile_claim_conflict(guest_stats, cloud_stats)
signal cleanup_completed
signal migration_completed
signal delete_completed
signal score_sync_finished(success)

var last_refresh_time = 0
var _is_fetching_leaderboards = false
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

var cached_guest_auth = {}
var cached_guest_stats = {}

var target_cloud_uid = ""
var cached_cloud_stats = {}

var _cached_link_stats = {}
var js_callback = null

var is_config_available = false

func _ready():
	var env = ConfigFile.new()
	var err = env.load(config_file_path)
	is_config_available = (err == OK)
	if not is_config_available:
		printerr("[Firebase Error] >> .env file is missing at res://addons/godot-firebase/.env. Leaderboard is disabled on this build.")
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
	
	var dir = Directory.new()
	if dir.file_exists("user://user.auth"):
		if OS.is_debug_build():
			print("[Debug] Auth file found. Restoring session...")
		Firebase.Auth.check_auth_file()
	else:
		if OS.is_debug_build():
			print("[Debug] No auth file found. Logging in anonymously...")
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
	_temp_all_time.clear()
	_temp_seasonal.clear()
	if OS.is_debug_build():
		var name_str = Global.player_name if Global.player_name != "" else "Guest"
		print("[Debug] Successfully connected and authenticated to Firebase.")
		print("[Debug] User Logged In as: ", name_str, " (UID: ", user_id, ")")
	else:
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
	if OS.is_debug_build():
		var name_str = Global.player_name if Global.player_name != "" else "Guest"
		print("[Debug] Connection to Firebase active and verified.")
		print("[Debug] Token Refreshed for: ", name_str, " (UID: ", user_id, ")")
	else:
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
	_temp_all_time.clear()
	_temp_seasonal.clear()
	emit_signal("auth_state_changed", false)
	if OS.is_debug_build():
		print("[Debug] User Logged Out: ", Global.player_name)
	else:
		print("User Logged Out")

func get_is_registered() -> bool:
	if not is_logged_in or user_id == "" or not Firebase.Auth.auth:
		return false
	var email = Firebase.Auth.auth.get("email", "")
	# Guests have no email or a dummy one, regular users have a real email
	return email != "" and email != "null"

func get_current_user_id() -> String:
	if is_logged_in and user_id != "":
		return user_id
	return ""

func is_claiming_profile() -> bool:
	return current_auth_state != AuthStates.ANONYMOUS_SESSION

func submit_score(score: int, mode: int, player_name: String, level: int, force_overwrite: bool = false):
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
		"level": level,
		"player_name": player_name,
		"timestamp": OS.get_unix_time(),
		"is_registered": is_registered
	}
	
	var time_dict = OS.get_datetime(true)
	var period_str = str(time_dict.year) + "-" + str(time_dict.month).pad_zeros(2)
	var seasonal_data = data.duplicate()
	seasonal_data["period"] = period_str
	
	var success1 = yield(_upsert_doc(all_time_collection, uid, data, force_overwrite), "completed")
	var success2 = yield(_upsert_doc(seasonal_collection, uid, seasonal_data, force_overwrite), "completed")
	var success = success1 and success2
	if OS.is_debug_build():
		if success:
			print("[Debug] Leaderboard score successfully synced to Firestore for: ", player_name, " - Score: ", score)
		else:
			print("[Debug] Leaderboard score sync FAILED for: ", player_name)
	if success:
		fetch_leaderboards(true)
	emit_signal("score_sync_finished", success)

func _upsert_doc(collection, uid, data, force_overwrite: bool = false) -> bool:
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
				var existing_reg = doc.get_value("is_registered")
				if existing_reg == null:
					existing_reg = false
				else:
					existing_reg = bool(existing_reg)
				var new_reg = bool(data.get("is_registered", false))
				
				var name_changed = (new_name != "" and existing_name != new_name)
				var reg_changed = (existing_reg != new_reg)
				
				if name_changed or reg_changed:
					if OS.is_debug_build():
						var col_type = "All-Time" if "alltime" in collection.collection_name else "Seasonal"
						print("[Debug] [Firebase ", col_type, "] Score is not higher, but info changed (name_changed: ", name_changed, ", reg_changed: ", reg_changed, "). Updating entry.")
					doc.add_or_update_field("player_name", new_name if new_name != "" else existing_name)
					doc.add_or_update_field("timestamp", OS.get_unix_time())
					doc.add_or_update_field("is_registered", new_reg)
					result = yield(collection.update(doc), "completed")
					return result != null
				else:
					if OS.is_debug_build():
						var col_type = "All-Time" if "alltime" in collection.collection_name else "Seasonal"
						print("[Debug] [Firebase ", col_type, "] Score not higher, name and registration status unchanged. Skipping update.")
					return true
		
		for k in data:
			doc.add_or_update_field(k, data[k])
		result = yield(collection.update(doc), "completed")
	else:
		result = yield(collection.add(uid, data), "completed")
	return result != null
	
func fetch_leaderboards(force_refresh: bool = false):
	if not is_config_available:
		emit_signal("leaderboard_updated", null, null)
		return
		
	if not force_refresh and not _temp_all_time.empty() and not _temp_seasonal.empty():
		if OS.is_debug_build():
			print("[Debug] Leaderboard fetched from local cache.")
		emit_signal("leaderboard_updated", _temp_all_time, _temp_seasonal)
		return
		
	if _is_fetching_leaderboards:
		if OS.is_debug_build():
			print("[Debug] Leaderboard fetch already in progress. Ignoring duplicate request.")
		return
		
	_is_fetching_leaderboards = true
		
	var start_time = OS.get_ticks_msec()
		
	var all_time_query = FirestoreQuery.new()
	all_time_query.from("leaderboard_rushybird_alltime", false)
	all_time_query.order_by("score", FirestoreQuery.DIRECTION.DESCENDING)
	all_time_query.limit(50)
	
	var all_time_result = yield(Firebase.Firestore.query(all_time_query), "completed")
	_on_all_time_result(all_time_result)
	
	var time_dict = OS.get_datetime(true)
	var period_str = str(time_dict.year) + "-" + str(time_dict.month).pad_zeros(2)
	
	var seasonal_query = FirestoreQuery.new()
	seasonal_query.from("leaderboard_rushybird_seasonal", false)
	seasonal_query.where("period", FirestoreQuery.OPERATOR.EQUAL, period_str)
	seasonal_query.order_by("score", FirestoreQuery.DIRECTION.DESCENDING)
	seasonal_query.limit(50)
	
	var seasonal_result = yield(Firebase.Firestore.query(seasonal_query), "completed")
	_on_seasonal_result(seasonal_result)

	if OS.is_debug_build():
		if all_time_result != null and seasonal_result != null:
			print("[Debug] Successfully connected and retrieved data from Firebase Firestore.")
		else:
			print("[Debug] Warning: Retrieved empty or partial leaderboard data from Firestore.")
		print("[Debug] Leaderboard fetch took ", OS.get_ticks_msec() - start_time, " ms")
		

		
	_is_fetching_leaderboards = false

var _temp_all_time = []
var _temp_seasonal = []

func _on_all_time_result(result):
	if result != null and typeof(result) == TYPE_ARRAY:
		_temp_all_time = []
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
	if result != null and typeof(result) == TYPE_ARRAY:
		_temp_seasonal = []
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

func submit_stats(player_data: Dictionary):
	if not is_config_available:
		emit_signal("stats_sync_finished", false, 0)
		return
		
	var uid = get_current_user_id()
	if uid == "":
		emit_signal("stats_sync_finished", false, 0)
		return
		
	var stats_collection = Firebase.Firestore.collection("player_data_rushybird")
	
	player_data["uid"] = uid
	player_data["is_registered"] = get_is_registered()
	player_data["last_updated"] = OS.get_unix_time()
	
	var success = yield(_upsert_doc(stats_collection, uid, player_data), "completed")
	if OS.is_debug_build():
		if success:
			print("[Debug] Player stats successfully synced to Firestore for: ", Global.player_name)
		else:
			print("[Debug] Player stats sync FAILED for: ", Global.player_name)
	emit_signal("stats_sync_finished", success, player_data.get("last_updated", OS.get_unix_time()) if success else 0)
# --- Profile Linking & Conflict Handling ---

var _cached_link_email = ""
var _cached_link_password = ""
var _cached_link_oauth_token = ""
var _cached_link_oauth_provider = null

func start_profile_claim_email(email: String, password: String, player_data: Dictionary):
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
	cached_guest_stats = player_data.duplicate()
	
	
	_cached_link_email = email
	_cached_link_password = password
	_cached_link_oauth_token = ""
	
	Firebase.Auth.link_with_email_and_password(cached_guest_auth.idtoken, email, password)

func start_profile_claim_oauth(token: String, provider, player_data: Dictionary):
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
	cached_guest_stats = player_data.duplicate()
	
	
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
	var collection = Firebase.Firestore.collection("player_data_rushybird")
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
		var changed_name_logged = doc.get_value("has_changed_name_logged_in")
		
		cached_cloud_stats = {
			"player_name": str(p_name) if p_name != null else "",
			"classic_highscore": int(classic_hs) if classic_hs != null else 0,
			"escalation_highscore": int(escalation_hs) if escalation_hs != null else 0,
			"escalation_highest_level": int(escalation_hl) if escalation_hl != null else 1,
			"total_games": int(games) if games != null else 0,
			"total_deaths": int(deaths) if deaths != null else 0,
			"total_revives": int(revives) if revives != null else 0,
			"total_distance": float(dist) if dist != null else 0.0,
			"playtime": float(play) if play != null else 0.0,
			"has_changed_name_logged_in": bool(changed_name_logged) if changed_name_logged != null else false
		}
		print("[FirebaseManager] Parsed cloud stats: ", cached_cloud_stats)
	else:
		print("[FirebaseManager] No cloud stats doc found or document type invalid. doc = ", doc)
		cached_cloud_stats = {
			"player_name": "",
			"classic_highscore": 0, "escalation_highscore": 0, "escalation_highest_level": 1,
			"total_games": 0, "total_deaths": 0, "total_revives": 0, "total_distance": 0.0, "playtime": 0.0,
			"has_changed_name_logged_in": false
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
	
	submit_stats(cached_guest_stats)
	yield(self, "stats_sync_finished")
	
	# Delete existing cloud leaderboard entries to permit overwriting with lower score (bypasses update rule via create)
	var alltime_col = Firebase.Firestore.collection("leaderboard_rushybird_alltime")
	_delete_doc(alltime_col, user_id)
	yield(self, "delete_completed")
	
	var seasonal_col = Firebase.Firestore.collection("leaderboard_rushybird_seasonal")
	_delete_doc(seasonal_col, user_id)
	yield(self, "delete_completed")
	
	var score = int(cached_guest_stats.get("escalation_highscore", 0))
	if score > 0: 
		submit_score(score, 1, cached_guest_stats.get("player_name", ""), int(cached_guest_stats.get("escalation_highest_level", 1)), true)
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
	_set_active_auth(cached_guest_auth)
	Firebase.Auth.save_auth(cached_guest_auth)
	Firebase.Auth.begin_refresh_countdown()
	user_id = cached_guest_auth.localid
	is_logged_in = true
	emit_signal("auth_state_changed", true)
	current_auth_state = AuthStates.ANONYMOUS_SESSION
	
	if OS.is_debug_build():
		var name_str = Global.player_name if Global.player_name != "" else "Guest"
		print("[Debug] Profile claim cancelled. Reverted to guest session: ", name_str, " (UID: ", user_id, ")")

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
	yield(collection.delete(doc), "completed")
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
	
	var stats_col = Firebase.Firestore.collection("player_data_rushybird")
	_delete_doc(stats_col, guest_uid)
	yield(self, "delete_completed")
	
	print("[Firebase] Deleting anonymous guest account from Firebase Authentication...")
	Firebase.Auth.delete_user_account()
	var auth_result : Array = yield(Firebase.Auth, "auth_request")
	var status_code = auth_result[0] if typeof(auth_result) == TYPE_ARRAY and auth_result.size() > 0 else "Unknown"
	print("[Firebase] Guest auth account deletion finished. Status: ", status_code)
	
	_set_active_auth(permanent_auth)
	print("[Firebase] Clean up complete for guest UID: ", guest_uid)
	emit_signal("cleanup_completed")

func _migrate_guest_data_to_new_user(guest_uid: String):
	print("[Firebase] Migrating guest data to new user ID: ", user_id)
	
	submit_stats(cached_guest_stats)
	yield(self, "stats_sync_finished")
	
	var score = int(cached_guest_stats.get("escalation_highscore", 0))
	if score > 0: 
		submit_score(score, 1, cached_guest_stats.get("player_name", ""), int(cached_guest_stats.get("escalation_highest_level", 1)))
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

func start_google_login(player_data: Dictionary):
	if OS.get_name() == "Android":
		print("[FirebaseManager] Google login is temporarily disabled on Android.")
		emit_signal("profile_claim_failed", "Google login is temporarily disabled on Android.")
		return

	_cached_link_stats = player_data.duplicate()
	cached_guest_stats = player_data.duplicate()
	
	
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
		
		_cached_link_email = ""
		_cached_link_password = ""
		_cached_link_oauth_token = code
		_cached_link_oauth_provider = provider
		
		Firebase.Auth.link_with_oauth(cached_guest_auth.idtoken, code, provider)
	else:
		Firebase.Auth.login_with_oauth(code, provider)

func _on_firestore_error(error_dict):
	print("[Firebase Firestore Error] ", error_dict)
