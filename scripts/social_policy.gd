extends RefCounted
## Client contract defaults. Server must enforce the same limits independently.
const TEXT_LIMIT := 2000
const NOTE_LIMIT := 120
const REMARK_LIMIT := 40
const REPORT_LIMIT := 500
const QUANTITY_LIMIT := 1000000
const UNANSWERED_GREETING_LIMIT := 1
const EXCHANGE_DAILY_LIMIT := -1 # No extra exchange daily quota; server may configure a policy.
const INVITATIONS_RESERVE_STOCK := false
const PAGE_SIZE := 40
const POLL_SECONDS := 8.0
