extends Control

@onready var is_server_using_tls: bool = $RESTHttpServer.use_tls
@onready var server_url: String = ("https://" if is_server_using_tls else "http://") + ("127.0.0.1:%d" % $RESTHttpServer.port)

@onready var api_v1_prefix: String = $RESTHttpServer/APIHandler_v1.path_prefix
@onready var api_v2_prefix: String = $RESTHttpServer/APIHandler_v2.path_prefix

@onready var http_client := $HTTPRequestClient

var list_of_users := []
var user_data: Dictionary = {}

# Pages is loaded as a GDScript instance (script-inside-a-script, as RefCounted)
# This is just so we can move some code away from here and avoid clutter
var pages := preload("res://addons/rest_api_server/example/pages.gd").new()


# ==============================================================================
# API HANDLING
# ==============================================================================

# -----------------------------------------
# GENERAL

# Handles endpoints which are not found in any API Handler
func _on_rest_http_server_no_handler_found(request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	print("No handler found for path: ", request.path)
	
	response.send(
		404, 
		JSON.stringify({"status": "error", "message": "Error 404: this endpoint is not supported"}), 
		"application/json"
	)

# Indexhandler - Handles the index endpoints (path is just `/`)
func _on_index_handler_get_requested(_endpoint: String, _params: Dictionary, _request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	response.send(200, 
		pages.format_page(pages.PAGE_INDEX, {
			"server_url_v1": server_url + api_v1_prefix,
			"server_url_v2": server_url + api_v2_prefix,
		})
	)


# -----------------------------------------
# VERSION 1 - HYBRID OF API AND WEB SERVER

func _on_api_handler_v_1_get_requested(endpoint: String, params: Dictionary, request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	match endpoint:
		"", "/":
			response.send(200, 
				pages.format_page(pages.VER_1_LIST_ITEMS, {
					"title": "List of endpoints (after \"/api/v1\")",
					"endpoint": pages.array_to_html_list(["/"]),
					"data": pages.array_to_html_list([
						"<code>/</code> - Lists endpoints",
						"<code>/users</code> - Lists users",
						"<code>/users/&lt;username&gt;</code> - Shows user properties",
					], "list_props"),
				})
			)
			
		"/users":
			var endpoint_breadcrumbs: Array = Array(endpoint.split("/"))
			
			var userlist := []
			for user in list_of_users:
				userlist.append("<code>%s</code>" % user)
			
			response.send(200, 
				pages.format_page(pages.VER_1_LIST_ITEMS, {
					"title": "Endpoint:",
					"endpoint": pages.array_to_html_list(endpoint_breadcrumbs),
					"data": pages.array_to_html_list(userlist, "list_props"),
				})
			)
		
		"/users/:username":
			var username: String = params["username"]
			if not username in user_data:
				response.send(200, 
					pages.format_page(pages.VER_1_ERROR, 
						{"message": "The username <code>%s</code> was not found" % username}
					)
				)
				return
			
			var data := []
			for item in user_data[username]:
				data.append("<code>%s</code>: <mark>%s</mark>" % [item, user_data[username][item]])
			
			response.send(200, 
				pages.format_page(pages.VER_1_LIST_ITEMS, {
					"title": "Endpoint:",
					"endpoint": pages.array_to_html_list(["users", username]),
					"data": pages.array_to_html_list(data, "list_props"),
				})
			)
			
			


# -----------------------------------------
# VERSION 2 - PURE REST API

func _on_api_handler_v_2_get_requested(endpoint: String, params: Dictionary, request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	match endpoint:
		
		"/users":
			response.send(
				200, 
				JSON.stringify({"users": list_of_users}), 
				"application/json"
			)
		
		"/users/:username":
			var username: String = params["username"]
			if not username in user_data:
				response.send(404, JSON.stringify({"error": "The username \"%s\" was not found" % username}), "application/json")
				return
			
			var data: Dictionary = user_data[username]
			response.send(200, JSON.stringify({"username": username, "data": data}), "application/json")
			return
		
		"/users/:username/:property":
			var username: String = params["username"]
			var property: String = params["property"]
			
			if not username in user_data:
				response.send(404, JSON.stringify({"error": "The username \"%s\" was not found" % username}), "application/json")
				return
			
			var data: Dictionary = user_data[username]
			if not property in data:
				response.send(404, JSON.stringify({"error": "Property \"%s\" not found in database for username \"%s\"" % [property, username]}), "application/json")
				return
			
			response.send(200, JSON.stringify({"username": username, "property": property, "value": data[property]}), "application/json")
			return


# ==============================================================================
# USER INTERFACE


func _ready() -> void:
	if $RESTHttpServer.use_tls:
		$PanelClient/EditServer.text = "https://127.0.0.1:%d" % $RESTHttpServer.port
		
		# Terrible workaround while a client node is not yet developed
		$HTTPRequestClient.set_tls_options(TLSOptions.client_unsafe(
			load($RESTHttpServer.tls_key_path)
		))
	else:
		$PanelClient/EditServer.text = "http://127.0.0.1:%d" % $RESTHttpServer.port
		
	
	_on_btn_reload_pressed()


func client_perform_request(method: HTTPClient.Method, endpoint: String, data: String = "") -> String:
	var headers: Array = ["Content-type: application/json"] if (method in [HTTPClient.METHOD_PUT, HTTPClient.METHOD_POST]) else []
	
	var server_addr: String = $PanelClient/EditServer.text
	var err: int = http_client.request(server_addr + endpoint, PackedStringArray(headers), method, data)
	if err != OK:
		return "(HTTPRequest error: %d)" % err
	
	var result: Array = await http_client.request_completed
	if result[1] != 200:
		if result[1] == 404:
			return "(Error 404 - not found)\n"
		
		var s := ""
		s += "(HTTPRequest status: %d, response code: %d)\n" % [
			result[0], result[1]
		]
		if (result[0] == 4) and $RESTHttpServer.use_tls and (server_addr.begins_with("http://")):
				s += "(Server uses https:// but client is trying http://)\n"
		if (result[0] == 5):
			if $RESTHttpServer.use_tls and (server_addr.begins_with("https://")):
				s += "(This could be certificate mismatch between client and server)\n"
			if (not $RESTHttpServer.use_tls) and (server_addr.begins_with("https://")):
				s += "(Server uses http:// but client is trying https://)\n"
		s += "Raw received response below:\n---\n%s\n" % [
			JSON.stringify(result, "    ")
		]
		return s
	
	# headers = Array(result[2]) # not needed for now
	var body_bytes: PackedByteArray = result[3]
	var body_text: String = body_bytes.get_string_from_utf8()
	
	if (body_text.begins_with("{") and body_text.ends_with("}")):
		# Identation for more pretty-looking JSON
		return JSON.stringify(
			JSON.parse_string(body_text),
			"    "
		)
	
	else:
		return body_text



func _on_btn_reload_pressed() -> void:
	var new_data = JSON.parse_string($PanelUsers/TextEditUsers.text)
	if not new_data:
		OS.alert("The provided JSON string could not be parsed. The database was not modified.", "Error")
		return
	
	list_of_users = new_data.keys()
	user_data = new_data


func _on_btn_client_get_pressed() -> void:
	$PanelClient/EditContent.text = "(Connecting...)"
	$PanelClient/EditContent.text = await client_perform_request(
		HTTPClient.METHOD_GET, 
		$PanelClient/EditPath.text,
		""
	)


func _on_btn_client_put_pressed() -> void:
	var content: String = $PanelClient/EditContent.text
	$PanelClient/EditContent.text = "(Connecting...)"
	$PanelClient/EditContent.text = await client_perform_request(
		HTTPClient.METHOD_PUT, 
		$PanelClient/EditPath.text,
		content
	)


func _on_btn_client_post_pressed() -> void:
	var content: String = $PanelClient/EditContent.text
	$PanelClient/EditContent.text = "(Connecting...)"
	$PanelClient/EditContent.text = await client_perform_request(
		HTTPClient.METHOD_POST, 
		$PanelClient/EditPath.text,
		content
	)


func _on_btn_client_delete_pressed() -> void:
	$PanelClient/EditContent.text = "(Connecting...)"
	$PanelClient/EditContent.text = await client_perform_request(
		HTTPClient.METHOD_GET, 
		$PanelClient/EditPath.text,
		""
	)
