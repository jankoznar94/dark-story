extends SceneTree
## WHAT CODE IS ACTUALLY IN THE DEPLOYED WEB BUILD?
##
## Answering Jan's "is the fix live?" needs evidence from the artifact the browser
## downloads, not from a commit hash. Two methods were tried and ONE of them lies:
##
##   * grepping the .pck for a script's STRING LITERALS reports 0 hits for strings
##     that are provably present ("Tělo", "Batoh je plný" both came back 0) - the
##     build is COMPRESSED, so only the uncompressed file table matches. A pass/fail
##     based on that would have been meaningless in both directions.
##   * the honest check is the SERVICE WORKER's CODE_VERSION: it is a hash of
##     index.html + index.js + index.pck + the icons + worklets, computed at build
##     time by tools/patch_web_sw.py. It changes if and only if the code in the
##     served build changes, so comparing it across two deploys proves which one a
##     browser will fetch as new - and a change with an UNCHANGED ASSET_VERSION is
##     also the proof that index.wasm was kept.
##
## The real acceptance for the corpse/panel fix is the LIVE BROWSER run with
## tools/web_console_probe.py plus a click sequence, and that is what the notes
## beside this file describe. This probe only closes the "is it deployed" question.
##
## Run: godot --headless --path . --script res://tools/probe_deployed_build.gd

const URL := "https://jankoznar94.github.io/dark-story/index.service.worker.js"

var _http: HTTPRequest
var _done := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_http = HTTPRequest.new()
	root.add_child(_http)
	_http.request(URL)
	# `request_completed` is a SIGNAL: awaiting it yields an Array
	# [result, response_code, headers, body] - not an int. Declaring the result
	# `int` is a parse error, which is the trap this project has hit before with
	# `var x = <dynamic>`; declare it `Variant` and index it.
	var res: Variant = await _http.request_completed
	var code: int = int(res[1])
	var body: PackedByteArray = res[3]
	print("HTTP %d, %d bytes" % [code, body.size()])
	var txt := body.get_string_from_utf8()
	for line in txt.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("const CODE_VERSION") or t.begins_with("const ASSET_VERSION"):
			print("  ", t)
	var has_new: bool = txt.contains("ASSET_FILES") and txt.contains("dark-story-wasm-")
	print("the deployed worker uses the split cache: %s" % str(has_new))
	print("PROBE_DONE")
	quit()
