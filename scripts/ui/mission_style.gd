class_name MissionStyle
extends RefCounted
## Gemeinsame Farben, Schriften und Bausteine der Missions-Oberflaeche.
##
## Bewusst als Code-Konstanten statt als Theme-Resource: Das HUD baut jeden
## Control selbst auf, ein Theme wuerde also nichts vererben, waere aber im
## Diff unlesbar. So liegt die gesamte Gestaltung an einer Stelle und ist
## nachvollziehbar versionierbar.
##
## Die Palette ist aus den vorhandenen Marsmaterialien (mars_sky.tres,
## mars_regolith.tres) abgeleitet, damit sich das HUD in den Farbraum der
## Szene einfuegt statt dagegen zu arbeiten.

# --- Farben ---------------------------------------------------------------

## Bernstein: Kopfzeile, Rahmen, aktives Ziel.
const AMBER := Color(0.941, 0.663, 0.231)
const AMBER_DIM := Color(0.941, 0.663, 0.231, 0.55)
const AMBER_FAINT := Color(0.941, 0.663, 0.231, 0.22)

## Heller Fliesstext.
const TEXT_BRIGHT := Color(0.945, 0.925, 0.898)
## Gedaempft: noch gesperrte Ziele.
const TEXT_MUTED := Color(0.541, 0.482, 0.431)
## Erfuellte Ziele.
const DONE_GREEN := Color(0.435, 0.749, 0.498)
const DONE_TEXT := Color(0.478, 0.541, 0.494)

## Panelhintergrund: warmes Fast-Schwarz.
const PANEL_BG := Color(0.055, 0.043, 0.039, 0.82)

## Wegpunktmarker.
const WAYPOINT := Color(0.42, 0.80, 0.92)
const WAYPOINT_DIM := Color(0.42, 0.80, 0.92, 0.65)

## Kurzes Aufblitzen beim Erfuellen eines Ziels.
const FLASH := Color(1.0, 1.0, 1.0)

# --- Masse ----------------------------------------------------------------

const PANEL_WIDTH := 340.0
const PANEL_MARGIN := 26.0
const PANEL_PADDING_H := 16.0
const PANEL_PADDING_V := 14.0
const ROW_SPACING := 7
const CORNER_BRACKET := 14.0

const FONT_SIZE_EYEBROW := 13
const FONT_SIZE_TITLE := 21
const FONT_SIZE_OBJECTIVE := 15
const FONT_SIZE_COUNTER := 14
const FONT_SIZE_BANNER := 17

const ICON_DIR := "res://assets/ui/icons/"

# --- Schriften ------------------------------------------------------------

## Technisch wirkende Kopfschrift: Standardschrift mit Sperrung.
##
## Das Projekt enthaelt bewusst keine Schriftdateien -- eine gesperrte,
## halbfette Variante der Engine-Schrift erzeugt den Leitstellen-Charakter
## ohne zusaetzliche Lizenzpflichten. Wird spaeter eine OFL-Schrift unter
## assets/ui/fonts/ abgelegt, genuegt hier eine Zeile.
static func header_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = 2
	font.variation_embolden = 0.15
	return font


static func body_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = 1
	return font


# --- Bausteine ------------------------------------------------------------

## Laedt ein Symbol aus assets/ui/icons/. Die SVGs sind rein weiss, die
## Faerbung uebernimmt modulate.
static func icon(icon_name: String) -> Texture2D:
	var path := ICON_DIR + icon_name + ".svg"
	if not ResourceLoader.exists(path):
		push_warning("MissionStyle: Symbol '%s' nicht gefunden." % path)
		return null
	return load(path) as Texture2D


## Hintergrund des Missionspanels. Der Rahmen wird vom MissionPanelFrame
## gezeichnet, damit er animierbar bleibt.
static func panel_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_BG
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	box.content_margin_left = PANEL_PADDING_H
	box.content_margin_right = PANEL_PADDING_H
	box.content_margin_top = PANEL_PADDING_V
	box.content_margin_bottom = PANEL_PADDING_V
	return box


## Farbe fuer einen Zielzustand.
static func state_color(state: int) -> Color:
	match state:
		MissionManager.State.ACTIVE:
			return AMBER
		MissionManager.State.DONE:
			return DONE_GREEN
		_:
			return TEXT_MUTED


## Symbolname fuer einen Zielzustand.
static func state_icon_name(state: int) -> String:
	match state:
		MissionManager.State.ACTIVE:
			return "obj_active"
		MissionManager.State.DONE:
			return "obj_done"
		_:
			return "obj_pending"


## Entfernung lesbar formatieren.
static func format_distance(meters: float) -> String:
	if meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	return "%d m" % int(round(meters))
