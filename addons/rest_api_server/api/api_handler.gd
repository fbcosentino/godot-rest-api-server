class_name RESTApiHandler
extends Node

## Signal emitted when a DELETE request is received, where [code]endpoint[/code]
## is the original endpoint mask string in the APIHandler which caused the match,
## [code]params[/code] is a [code]Dictionary[/code] containing the parameter values
## (check the [code]endpoints[/code] property for more information), [code]request[/code]
## contains information on the received request, and [code]response[/code] shoud be
## used to send a response to the request. You [b]must[/b] send a response in the
## handler function, otherwise the client will assume the server is offline.
signal delete_requested(endpoint: String, params: Dictionary, request: RESTHttpRequest, response: RESTHttpResponse)

## Signal emitted when a GET request is received, where [code]endpoint[/code]
## is the original endpoint mask string in the APIHandler which caused the match, and
## [code]params[/code] is a [code]Dictionary[/code] containing the parameter values
## (check the [code]endpoints[/code] property for more information), [code]request[/code]
## contains information on the received request, and [code]response[/code] shoud be
## used to send a response to the request. You [b]must[/b] send a response in the
## handler function, otherwise the client will assume the server is offline.
signal get_requested(endpoint: String, params: Dictionary, request: RESTHttpRequest, response: RESTHttpResponse)

## Signal emitted when a POST request is received, where [code]endpoint[/code]
## is the original endpoint mask string in the APIHandler which caused the match, and
## [code]params[/code] is a [code]Dictionary[/code] containing the parameter values
## (check the [code]endpoints[/code] property for more information), [code]body[/code]
## contains the posted content decoded as per the "Content-type" header (see
## [code]RESTHttpRequest.get_body_parsed()[/code] for details), [code]request[/code]
## contains information on the received request, and [code]response[/code] shoud be
## used to send a response to the request. You [b]must[/b] send a response in the
## handler function, otherwise the client will assume the server is offline.
signal post_requested(endpoint: String, params: Dictionary, body: Variant, request: RESTHttpRequest, response: RESTHttpResponse)

## Signal emitted when a PUT request is received, where [code]endpoint[/code]
## is the original endpoint mask string in the APIHandler which caused the match, and
## [code]params[/code] is a [code]Dictionary[/code] containing the parameter values
## (check the [code]endpoints[/code] property for more information), [code]body[/code]
## contains the put content decoded as per the "Content-type" header (see
## [code]RESTHttpRequest.get_body_parsed()[/code] for details), [code]request[/code]
## contains information on the received request, and [code]response[/code] shoud be
## used to send a response to the request. You [b]must[/b] send a response in the
## handler function, otherwise the client will assume the server is offline.
signal put_requested(endpoint: String, params: Dictionary, body: Variant, request: RESTHttpRequest, response: RESTHttpResponse)


## Prefix added to all endpoints. If not blank, must start with a forward slash
## and not end with one. Example, if prefix is [code]"/api/v1"[/code], and one of the endpoints
## is [code]"/dashboard/prices"[/code], then the path to access this endpoint in this handler
## will be [code]"/api/v1/dashboard/prices"[/code]. If left blank, the endpoint is the path.
@export var path_prefix := "/api/v1"

## List of endpoints supported by this API handler. Must start with a forward slash.
## Start any element in the path with a colon (":") to turn it into a parameter: 
## that element of the path will accept any value, and the value will be provided
## in the [code]params[/code] Dictionary, having the parameter name defined here as the key.
## [br][br]
## Example: an endpoint [code]"/users/:user_id/summary/:page"[/code]
## means a GET request to the path [code]"/users/mary_123/summary/3"[/code] will emit the [code]get_requested[/code]
## signal having [code]endpoint[/code] as:[br]
##         [code]"/users/:user_id/summary/:page"[/code][br]
## and having [code]params[/code] as[br]
##         [code]{"user_id": "mary_123", "page": "3"}[/code][br]
## There can be any number of parameters, or none at all. 
@export var endpoints: Array[String] = []


var routers := {}


func _ready() -> void:
	var server: Node = get_parent()
	if not server is RESTHttpServer:
		return
	
	for endpoint: String in endpoints:
		if not endpoint in routers:
			var new_router = RESTApiRouter.new()
			new_router.handler = self
			new_router.endpoint = endpoint
			
			routers[endpoint] = new_router
			
			server.register_router(path_prefix + endpoint, new_router)
