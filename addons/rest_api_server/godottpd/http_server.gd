class_name RESTHttpServer
extends Node

## This signal is emitted when a request is received, but the path doesn't have
## any matching endpoint in any APIhandler. Usually used for 404 errors - or
## the equivalent in your API.
signal no_handler_found(request: RESTHttpRequest, response: RESTHttpResponse)

## If true, will auto-start the server when the Node is ready, and remain active
## until manually stopped.
@export var auto_start := false

## if true, will print debug messages to console
@export var enable_debug := false

@export_group("HTTP Server")

## The ip address to bind the server to. Use * for all IP addresses [*]
@export var bind_address: String = "*"

## The port to bind the server to. [8080]
@export var port: int = 8080

## The server identifier to use when responding to requests [GodotRestApi]
@export var server_identifier: String = "GodotRestApi"

@export_subgroup("SSL-TLS")

## If enabled, uses SSL/TLS for incoming connections
@export var use_tls := false

## SSL/TLS certificate file, e.g. res://tls_certificate.crt
@export var tls_certificate_path := "res://addons/rest_api_server/tls/certificate.crt"

## SSL/TLS key file, e.g. res://tls_private.key
@export var tls_key_path := "res://addons/rest_api_server/tls/private.key"

@export_subgroup("#")
@export_group("")

# If `RESTHttpRequest`s and `RESTHttpResponse`s should be logged
var _logging: bool = false

# The TCP server instance used
var _server: TCPServer

# An array of StraemPeerTCP objects who are currently talking to the server
var _clients: Array = []
var _appending_clients: Array = []

# A list of RESTHttpRequest routers who could handle a request
var _routers: Array = []

# A regex identifiying the method line
var _method_regex: RegEx = RegEx.new()

# A regex for header lines
var _header_regex: RegEx = RegEx.new()

# The base path used in a project to serve files
var _local_base_path: String = "res://src"

# list of host allowed to call the server
var _allowed_origins: PackedStringArray = []

# Comma separed methods for the access control
var _access_control_allowed_methods = "POST, GET, OPTIONS"

# Comma separed headers for the access control
var _access_control_allowed_headers = "content-type"

# Used only when use_tls == true
var _tlsoptions: TLSOptions

# Holds references of resources so they can be called outside their creation threads
var _response_queue := []
var _response_queue_mutex := Mutex.new()


# Compile the required regex
func _init(_logging: bool = false):
	self._logging = _logging
	set_process(false)
	_method_regex.compile("^(?<method>GET|POST|HEAD|PUT|PATCH|DELETE|OPTIONS) (?<path>[^ ]+) HTTP/1.1$")
	_header_regex.compile("^(?<key>[\\w-]+): (?<value>(.*))$")


func _ready() -> void:
	if auto_start:
		call_deferred("start")


# Print a debug message in console, if the debug mode is enabled
#
# #### Parameters
# - message: The message to be printed (only in debug mode)
func _print_debug(message: String) -> void:
	if enable_debug:
		var time = Time.get_datetime_dict_from_system()
		var time_return = "%02d-%02d-%02d %02d:%02d:%02d" % [time.year, time.month, time.day, time.hour, time.minute, time.second]
		print("[SERVER] ",time_return," >> ", message)

## Register a new router to handle a specific path
## [br]
## [br][param path] - The path the router will handle.
## Supports a regular expression and the group matches will be available in RESTHttpRequest.query_match.
## [br][param router] - The router which will handle the request
func register_router(path: String, router: RESTHttpRouter, condition: Callable = func(request: RESTHttpRequest): return true):
	var path_regex = RegEx.new()
	var params: Array = []
	if path.left(0) == "^":
		path_regex.compile(path)
	else:
		var regexp: Array = _path_to_regexp(path, router is RESTHttpFileRouter)
		path_regex.compile(regexp[0])
		params = regexp[1]
	_routers.push_back({
		"path": path_regex,
		"params": params,
		"router": router,
		"condition": condition,
	})


## Handle possibly incoming requests
func _process(_delta: float) -> void:
	if _server:
		while _server.is_connection_available():
			var new_client = _server.take_connection()
			if new_client:
				# postpone action to when the client is properly connected
				_appending_clients.append(new_client)
		
		# Established clients
		var client_list: Array = self._clients.duplicate() # duplicate since we are deleting
		for client in client_list:
			client.poll()
			var client_status: int = client.get_status()
			
			if client_status == StreamPeerTCP.STATUS_CONNECTED:
				var bytes = client.get_available_bytes()
				if bytes > 0:
					var request_string = client.get_utf8_string(bytes)
					self._handle_request(client, request_string)
			
			elif client_status != StreamPeerTCP.STATUS_CONNECTING: # also applies to StreamPeerTLS.STATUS_HANDSHAKING
				self._clients.erase(client)
		
		# Clients in connecting step
		client_list = _appending_clients.duplicate() # Must duplicate since we are removing
		for client in client_list: 
			client.poll()
			var client_status: int = client.get_status()
			
			if client_status == StreamPeerTCP.STATUS_CONNECTED:
				_appending_clients.erase(client)
				
				if use_tls:
					var tls_client := StreamPeerTLS.new()
					if tls_client.accept_stream(client, _tlsoptions) == OK:
						self._clients.append(tls_client)
					else:
						_print_debug("Error: attempting to create StreamPeerTLS for client failed. Client: " + str(client))
						client.disconnect_from_host()
				else:
					self._clients.append(client)
			
			elif client_status != StreamPeerTCP.STATUS_CONNECTING: # also applies to StreamPeerTLS.STATUS_HANDSHAKING
				_appending_clients.erase(client)
		
		
		while _response_queue.size() > 0:
			var resp_item: Array = _response_queue_pop()
			if not resp_item:
				break
			var target_node = resp_item[0]
			var method_name: StringName = resp_item[1]
			var args: Array = resp_item[2]
			var resp_client = resp_item[3]
			if (resp_client in self._clients) and (resp_client.get_status() == StreamPeerTCP.STATUS_CONNECTED):
				target_node.callv(method_name, args)


## Start the server
func start():
	if (tls_certificate_path == "") and (tls_key_path == ""):
		# Failed sanity check, just disable as the user might not know what this does
		use_tls = false
		_print_debug("In order to use SSL/TLS, you need a certificate and a key. For development purposes, you can generate a temporary one running res://addons/rest_api_server/tls/ssl_tls_generator.tscn")
		
	if use_tls:
		_tlsoptions = TLSOptions.server(
			load(tls_key_path), load(tls_certificate_path)
		)
	
	set_process(true)
	self._server = TCPServer.new()
	var err: int = self._server.listen(self.port, self.bind_address)
	match err:
		22:
			_print_debug("Could not bind to port %d, already in use" % [self.port])
			stop()
		_:
			_print_debug("HTTP Server listening on http://%s:%s" % [self.bind_address, self.port])


## Stop the server and disconnect all clients
func stop():
	for client in self._clients:
		client.disconnect_from_host()
	self._clients.clear()
	self._server.stop()
	set_process(false)
	_print_debug("Server stopped.")


# Interpret a request string and perform the request
#
# #### Parameters
# - client: The client that send the request
# - request: The received request as a String
func _handle_request(client: StreamPeer, request_string: String):
	var request = RESTHttpRequest.new()
	for line in request_string.split("\r\n"):
		var method_matches = _method_regex.search(line)
		var header_matches = _header_regex.search(line)
		if method_matches:
			request.method = method_matches.get_string("method")
			var request_path: String = method_matches.get_string("path")
			# Check if request_path contains "?" character, could be a query parameter
			if not "?" in request_path:
				request.path = request_path
			else:
				var path_query: PackedStringArray = request_path.split("?")
				request.path = path_query[0]
				request.query = _extract_query_params(path_query[1])
			request.headers = {}
			request.body = ""
		elif header_matches:
			request.headers[header_matches.get_string("key")] = \
			header_matches.get_string("value")
		else:
			request.body += line
	self._perform_current_request(client, request)


# Handle a specific request and send it to a router
# If no router matches, send a 404
#
# #### Parameters
# - client: The client that send the request
# - request_info: A dictionary with information about the request
#   - method: The method of the request (e.g. GET, POST)
#   - path: The requested path
#   - headers: A dictionary of headers of the request
#   - body: The raw body of the request
func _perform_current_request(client: StreamPeer, request: RESTHttpRequest):
	# Original GodotTPD uses Threads
	#var thread = Thread.new()
	#thread.start(__perform_current_request.bind(client, request))
	
	# This implementation doesn't, instead __perform_current_request is turned
	# into a coroutine we don't await
	__perform_current_request(client, request)


func __perform_current_request(client: StreamPeer, request: RESTHttpRequest):
	_print_debug("HTTP Request: " + str(request))
	var found = false
	var is_allowed_origin = false
	var response = RESTHttpResponse.new()
	var fetch_mode = ""
	var origin = ""
	response.client = client
	response.server_identifier = server_identifier

	if request.headers.has("Sec-Fetch-Mode"):
		fetch_mode = request.headers["Sec-Fetch-Mode"]
	elif request.headers.has("sec-fetch-mode"):
		fetch_mode = request.headers["sec-fetch-mode"]

	if request.headers.has("Origin"):
		origin = request.headers["Origin"]
	elif request.headers.has("origin"):
		origin = request.headers["origin"]

	if _allowed_origins.has(origin):
		is_allowed_origin = true
		response.access_control_origin = origin

	response.access_control_allowed_methods = _access_control_allowed_methods
	response.access_control_allowed_headers = _access_control_allowed_headers

	for router in self._routers:
		if not router.condition.bind(request).call(): break
		
		var matches = router.path.search(request.path)
		if matches:
			request.query_match = matches
			if request.query_match.get_string("subpath"):
				request.path = request.query_match.get_string("subpath")
			if router.params.size() > 0:
				for parameter in router.params:
					request.parameters[parameter] = request.query_match.get_string(parameter)
			match request.method:
				"GET":
					found = true
					_response_queue_append([router.router, &"handle_get", [request, response], client])
				"POST":
					found = true
					_response_queue_append([router.router, &"handle_post", [request, response], client])
				"HEAD":
					found = true
					_response_queue_append([router.router, &"handle_head", [request, response], client])
				"PUT":
					found = true
					_response_queue_append([router.router, &"handle_put", [request, response], client])
				"PATCH":
					found = true
					_response_queue_append([router.router, &"handle_patch", [request, response], client])
				"DELETE":
					found = true
					_response_queue_append([router.router, &"handle_delete", [request, response], client])
				"OPTIONS":
					if _allowed_origins.size() > 0 && fetch_mode == "cors":
						if is_allowed_origin:
							response.send(204)
						else:
							response.send(400, "%s is not present in the allowed origins" % origin)

						return

					found = true
					_response_queue_append([router.router, &"handle_options", [request, response], client])
			break
		
		# One StreamPeer per frame, in lieu of using threads
		await get_tree().process_frame
	
	if not found:
		_response_queue_append([self, &"emit_signal", ["no_handler_found", request, response], client])


func _response_queue_append(value: Array):
	_response_queue_mutex.lock()
	_response_queue.append(value)
	_response_queue_mutex.unlock()


func _response_queue_pop():
	_response_queue_mutex.lock()
	var value = _response_queue.pop_front()
	_response_queue_mutex.unlock()
	return value


# Converts a URL path to @regexp RegExp, providing a mechanism to fetch groups from the expression
# indexing each parameter by name in the @params array
#
# #### Parameters
# - path: The path of the RESTHttpRequest
# - should_match_subfolder: (dafult [false]) if subfolders should be matched and grouped,
#							used for HttpFileRouter
#
# Returns: A 2D array, containing a @regexp String and Dictionary of @params
# 			[0] = @regexp --> the output expression as a String, to be compiled in RegExp
# 			[1] = @params --> an Array of parameters, indexed by names
# 			ex. "/user/:id" --> "^/user/(?<id>([^/#?]+?))[/#?]?$"
func _path_to_regexp(path: String, should_match_subfolders: bool = false) -> Array:
	var regexp: String = "^"
	var params: Array = []
	var fragments: Array = path.split("/")
	fragments.pop_front()
	for fragment in fragments:
		if fragment.left(1) == ":":
			fragment = fragment.lstrip(":")
			regexp += "/(?<%s>([^/#?]+?))" % fragment
			params.append(fragment)
		else:
			regexp += "/" + fragment
	regexp += "[/#?]?$" if not should_match_subfolders else "(?<subpath>$|/.*)"
	return [regexp, params]


## Enable CORS (Cross-origin resource sharing) which only allows requests from the specified servers
## [br]
## [br][param allowed_origins] - The origins that are allowed to be accessed from this server
## [br][param access_control_allowed_methods] - The methods that are allowed to be used
## [br][param access_control_allowed_headers] - The headers that are allowed to be sent
func enable_cors(allowed_origins: PackedStringArray, access_control_allowed_methods : String = "POST, GET, OPTIONS", access_control_allowed_headers : String = "content-type"):
	_allowed_origins = allowed_origins
	_access_control_allowed_methods = access_control_allowed_methods
	_access_control_allowed_headers = access_control_allowed_headers


# Extracts query parameters from a String query,
# building a Query Dictionary of param:value pairs
#
# #### Parameters
# - query_string: the query string, extracted from the RESTHttpRequest.path
#
# Returns: A Dictionary of param:value pairs
func _extract_query_params(query_string: String) -> Dictionary:
	var query: Dictionary = {}
	if query_string == "":
		return query
	var parameters: Array = query_string.split("&")
	for param in parameters:
		if not "=" in param:
			continue
		var kv : Array = param.split("=")
		var value: String = kv[1]
		if value.is_valid_int():
			query[kv[0]] = value.to_int()
		elif value.is_valid_float():
			query[kv[0]] = value.to_float()
		else:
			query[kv[0]] = value
	return query
