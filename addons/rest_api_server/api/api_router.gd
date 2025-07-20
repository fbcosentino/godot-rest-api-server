## This is an intermediate class implemented to keep the RESTHttpServer as
## compatible as possible to the originalGodotTPD's HttpServer used as
## starting point for this library. You most likely won't have to touch this file.

extends RESTHttpRouter
class_name RESTApiRouter

var handler: RESTApiHandler
var endpoint: String

func handle_get(request: RESTHttpRequest, response: RESTHttpResponse):
	handler.get_requested.emit(
		endpoint, 
		request.parameters,
		request,
		response
	)


func handle_post(request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	handler.post_requested.emit(
		endpoint, 
		request.parameters,
		request.get_body_parsed(),
		request,
		response
	)


func handle_put(request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	handler.put_requested.emit(
		endpoint, 
		request.parameters,
		request.get_body_parsed(),
		request,
		response
	)


func handle_delete(request: RESTHttpRequest, response: RESTHttpResponse) -> void:
	handler.delete_requested.emit(
		endpoint, 
		request.parameters,
		request,
		response
	)
