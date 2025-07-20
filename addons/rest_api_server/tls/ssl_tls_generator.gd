extends Label

## Full text of domain used for certificate, e.g. localhost:8080
@export var tls_domain := "localhost:8080"

## Organization name used for certificate
@export var tls_organization_name := "A game company"

## Country code used for certificate
@export var tls_country := "GB"

## SSL/TLS certificate file, e.g. res://tls_certificate.crt
@export var tls_certificate_path := "res://addons/rest_api_server/tls/certificate.crt"

## SSL/TLS private key file, e.g. res://tls_private.key
@export var tls_key_path := "res://addons/rest_api_server/tls/private.key"


func _on_button_pressed() -> void:
	var crypto := Crypto.new()
	
	var key: CryptoKey = crypto.generate_rsa(4096)
	key.save(tls_key_path)
	
	var certificate: X509Certificate = crypto.generate_self_signed_certificate(
		key, 
		"CN=" + tls_domain + ",O=" + tls_organization_name + ",C=" + tls_country
	)
	certificate.save(tls_certificate_path)
