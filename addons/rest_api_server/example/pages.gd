extends RefCounted

const PAGE_INDEX := """<html data-theme="dark">
<head><link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/minstyle.io@2.0.2/dist/css/minstyle.io.min.css">
	<style>
.ms-card-title {
	border-bottom: 1px solid #777777;
}
	</style>
</head>
<body>

<header class="ms-footer ms-small"><div class="container"><p>
REST API Server
</p></div></header>

<p>&nbsp;</p>


<div class="ms-card ms-border" style="padding: 3%">
	<div class="ms-card-title">
		<h5>Welcome to the example project for the REST API Server plugin for Godot 4.x!</h5>
	</div>
	<div class="ms-card-content">
		<p>This example features 2 versions, with prefixes "/api/v1" and - very creatively - "/api/v2".
		Their features are separate, and handled via different signal handlers in the project.</p>
		
		<p>&nbsp;</p>
		
		<p>In terms of application, the difference between the two versions is <b>version 1</b> is a
		human-readable interface using pages provided by the server with HTML forms and links to interact
		(so it's a hybrid of an API with a normal web application),
		while <b>version 2</b> is a true REST API using JSON objects (so a user interface should be
		external).</p>
		
		<p>&nbsp;</p>
		
		<p>A simple REST API Client node is planned for a future version. For now you could use HTTPRequest.</p>
		
		<p>&nbsp;</p>
		
		<p>Pick your API version below:</p>
		
		<ul>
			<li class="ms-btn"><a href="{server_url_v1}">Version 1</a></li>
			<li class="ms-btn"><a href="{server_url_v2}">Version 2</a></li>
		</ul>
	</div>
</div>

<p>&nbsp;</p>

<footer class="ms-footer ms-small"><div class="container"><p>
by fbcosentino - <a href="https://github.com/fbcosentino/">Github</a>
</p></div></footer>
</body></html>
"""

const VER_1_ERROR := """<html data-theme="dark">
<head>
<link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/minstyle.io@2.0.2/dist/css/minstyle.io.min.css">
	<style>
.ms-card-title {
	border-bottom: 1px solid #777777;
}
	</style>
</head>
<body>

<div class="ms-card ms-border" style="padding: 3%">
	<div class="ms-card-title">
		<h5>ERROR</h5>
	</div>
	<div class="ms-card-content">
		{message}
	</div>
</div>

</body></html>
"""




const VER_1_LIST_ITEMS := """<html data-theme="dark">
<head>
<link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/minstyle.io@2.0.2/dist/css/minstyle.io.min.css">
	<style>
.ms-card-title {
	border-bottom: 1px solid #777777;
}
.list_props {
	line-height:180%;
}
	</style>
</head>
<body>

<div class="ms-card ms-border" style="padding: 3%">
	<div class="ms-card-title">
		<h5>{title}:
			<div class="ms-breadcrumb">
				{endpoint}
			</div>
		</h5>
	</div>
	<div class="ms-card-content">
		{data}
	</div>
</div>

</body></html>
"""



func format_page(page_source: String, format_vars: Dictionary) -> String:
	var result: String = page_source
	
	for var_name in format_vars:
		var var_code := "{%s}" % var_name
		if var_code in result:
			result = result.replace(var_code, format_vars[var_name])
	
	return result


func array_to_html_list(items: Array, class_li: String = "") -> String:
	var result := "<ul>\n"
	for item in items:
		result += "<li class=\"%s\">%s</li>\n" % [class_li, str(item)]
	result += "</ul>\n"
	
	return result
