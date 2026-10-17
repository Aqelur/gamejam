extends Resource
## One proposal a visitor brings to the desk.
##
## Each proposal is a .tres file in PresidentRoom/proposals/ (day_cycle.gd
## loads every file in that folder). Fill it in from the inspector:
##
##   id          unique name, also used by "unlocks" (e.g. "health_hospital")
##   character   who brings it ("Minister of Health")
##   start       true = can turn up from day 1; false = only once unlocked
##   first       true = always the very first paper of the game (before any
##               other start proposal)
##   says        what they say; printed on the paper
##   Denied / Approved
##     label     the short answer printed next to DENIED / APPROVED
##     people, money, readiness, bureaucracy   how much each stat changes
##     unlocks   id of the proposal this choice opens up ("" = none). If no
##               file has that id yet, nothing happens.
##     caption   the line shown over the city at the end of the day
##     action    what happens to city_target in the city: NONE or BUILD.
##               CONCERT puts up a one-night concert on the beach instead
##               (beach_concert.gd, no city_target needed); its caption can be
##               split into narrated lines with "|"
##     cutscene  a little 2D scene shown at the end of the day instead of the
##               city fly-over, with the caption read aloud (end_cutscene.gd):
##               NONE, NEWS_BROADCAST (TV news, Pac-Man anchor talking) or
##               CALM_CITY (cartoon city, sleeping fault underneath)
##     voice     optional recorded narration for the caption. Empty = the
##               caption is read by the system text-to-speech voice
##   city_target node path inside City/city.tscn that the end-of-day view
##               flies to, e.g. "Districts/CivicCenter/Buildings/Hospital".
##               Empty = this proposal doesn't show in the city.
##   note        designer note, not shown in game
##
## Stats map onto the four gauges on the desk plaque (president_room.gd Stat):
##   people -> People's Awareness, money -> Money,
##   readiness -> Infrastructure, bureaucracy -> Bureaucracy.

enum CityAction { NONE, BUILD, CONCERT }
enum Cutscene { NONE, NEWS_BROADCAST, CALM_CITY }

@export var id := ""
@export var character := ""
@export var start := false
@export var first := false
@export_multiline var says := ""

@export_group("Denied")
@export var deny_label := ""
@export_range(-100, 100) var deny_people := 0
@export_range(-100, 100) var deny_money := 0
@export_range(-100, 100) var deny_readiness := 0
@export_range(-100, 100) var deny_bureaucracy := 0
@export var deny_unlocks := ""
@export_multiline var deny_caption := ""
@export var deny_action := CityAction.NONE
@export var deny_cutscene := Cutscene.NONE
@export var deny_voice: AudioStream

@export_group("Approved")
@export var approve_label := ""
@export_range(-100, 100) var approve_people := 0
@export_range(-100, 100) var approve_money := 0
@export_range(-100, 100) var approve_readiness := 0
@export_range(-100, 100) var approve_bureaucracy := 0
@export var approve_unlocks := ""
@export_multiline var approve_caption := ""
@export var approve_action := CityAction.NONE
@export var approve_cutscene := Cutscene.NONE
@export var approve_voice: AudioStream

@export_group("City")
@export var city_target := ""

@export_group("")
@export_multiline var note := ""


## Stat changes in the order of president_room.gd Stat:
## [people, money, readiness, bureaucracy].
func effects(approved: bool) -> Array[int]:
	if approved:
		return [approve_people, approve_money, approve_readiness, approve_bureaucracy]
	return [deny_people, deny_money, deny_readiness, deny_bureaucracy]


func label(approved: bool) -> String:
	return approve_label if approved else deny_label


func unlocks(approved: bool) -> String:
	return approve_unlocks if approved else deny_unlocks


func caption(approved: bool) -> String:
	return approve_caption if approved else deny_caption


func action(approved: bool) -> CityAction:
	return approve_action if approved else deny_action


func cutscene(approved: bool) -> Cutscene:
	return approve_cutscene if approved else deny_cutscene


func voice(approved: bool) -> AudioStream:
	return approve_voice if approved else deny_voice


## The text printed on the paper.
func paper_body() -> String:
	var t := ""
	if character != "":
		t += "FROM THE %s\n\n" % character.to_upper()
	t += "“%s”" % says
	if approve_label != "" or deny_label != "":
		t += "\n\nAPPROVED — %s\nDENIED — %s" % [approve_label, deny_label]
	return t
