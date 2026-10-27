extends RefCounted
## Shared brand and motion parameters. Times are seconds, sizes are logical UI px.
const PRIMARY := Color("#092C87")
const HOVER_COLOR := Color("#092A80")
const PRESSED_COLOR := Color("#08287A")
const SOFT := Color("#EBEEF5")
const SOFT_HOVER := Color(9.0 / 255, 44.0 / 255, 135.0 / 255, 0.04)
const FOCUS_RING := Color(9.0 / 255, 44.0 / 255, 135.0 / 255, 0.28)
const ON_PRIMARY := Color.WHITE
# Existing accessible dark-theme foregrounds are centralized, not painted onto artwork.
const DARK_ACCENT := Color("#8DB5FF")
const DARK_SOFT := Color("#20375B")
const PRESS := 0.08
const HOVER := 0.14
const STATE := 0.12
# Selected tab underline expands from the center; duration is in seconds.
const TAB_UNDERLINE := 0.70
const PANEL := 0.18
const PAGE := 0.18
const EXIT := 0.12
# Trend lines/dots and progress fills reveal from left to right in seconds.
const DATA := 1.70
const REWARD := 0.4
const PET := 0.5
const CHEVRON := 0.16
const TOOLTIP_DELAY := 0.3
const TOOLTIP := 0.1
const LOADING_DELAY := 0.2
const LOADING_TURN := 0.9
