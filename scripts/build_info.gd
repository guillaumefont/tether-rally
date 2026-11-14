# What this build is. CI (.github/workflows/build.yml) rewrites this file before exporting;
# the values here are for builds made by hand (editor, tests), which never update themselves.
#   BUILD    the workflow run number (only grows; the APK's versionCode is 100 + BUILD)
#   SHELL    fingerprint of everything an update of the game data alone can't change
#            (engine version, project.godot, export presets, scripts/self_update.gd)
#   ENGINE   Godot version the build was exported with
#   CHANNEL  the Pages folder this build comes from and checks for updates ("" = none)
extends RefCounted

const BUILD := 0
const SHELL := ""
const ENGINE := ""
const CHANNEL := ""
