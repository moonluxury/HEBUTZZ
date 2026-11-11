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
# PC acquisition stage. Seconds; carousel never determines a transaction result.
const CARD_STAGE_ENTER := 0.40
# Total deck entrance: show the pile, then spread it from left to right.
const CARD_POOL_ENTER := 0.45
const CARD_POOL_STACK_APPEAR := 0.06
# Seconds per card position: smaller = faster (e.g. 1.20 is faster than 1.60).
const CARD_POOL_STEP := 0.30
const CARD_POOL_SETTLE := 0.25
const CARD_POOL_TRAVEL_PER_SLOT := 0.14
const CARD_POOL_TRAVEL_MAX := 2.10
const CARD_POOL_EXTRACT := 0.45
# Display copies only; the server still owns the original seven-card odds.
const CARD_POOL_DISPLAY_COUNT := 11
# Fraction of normal speed while hovering: larger = less slowdown (0.40 = 40%).
const CARD_POOL_HOVER_SPEED := 0.30
const CARD_POOL_HOVER_RESPONSE := 0.14
# One circular arc supplies both positions and tangent angles (logical UI px).
const CARD_POOL_ARC_RADIUS := 3000.0
const CARD_POOL_SPACING := 112.0
# Selection feedback is parallel to the pool/request, never an extra reveal gate.
const CARD_PICK_DURATION := 0.45
const CARD_PICK_PARTICLES := 24
const CARD_PICK_RELEASE := 0.08
const CARD_PICK_REDUCED := 0.14
# Steady card-back light after selection; 0 disables, higher is brighter.
const CARD_PICK_BACK_LIGHT := 0.30
