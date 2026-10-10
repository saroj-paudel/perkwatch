# 00. Decisions

Fixed decisions for the build. If another doc disagrees, this file wins.

## Fixed decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Stack is Next.js (App Router) + TypeScript + Tailwind + Supabase | Owner's chosen stack |
| D2 | Telegram bot is the only notification channel. Email and Discord are later | Simplest to wire up, free |
| D3 | Single user. One owner account, restricted by `OWNER_EMAIL`, signups disabled | Prototype scope |
| D4 | Screenshots are processed in memory and never stored. No storage bucket, no cleanup job | Meets "screenshot deleted afterwards" in the strongest way and is simpler than store-then-delete |
| D5 | AI proposes, the user confirms. Nothing saves without confirmation | Models misread dates |
| D6 | Gemma 4 through the Gemini API, called only from the server | Keeps the key private |
| D7 | `expiring`, `expired` and `missed` are computed in TypeScript, not stored | One source of truth, timezone-aware |
| D8 | Stored statuses: `eligible`, `claimed`, `active`, `used`, `archived` | Matches the lifecycle, derived states are computed |
| D9 | Reminder thresholds default to 30, 14, 7, 3, 1 days. A missed threshold sends once as a catch-up | Survives a missed cron run and late-added perks |
| D10 | One daily cron run. No quiet hours in the MVP | Quiet hours are meaningless with one fixed run time |
| D11 | Perk create, update, delete and settings use Server Actions. Extraction, ask, cron and Telegram webhook are route handlers | Route handlers are needed for external callers and multipart uploads |
| D12 | The schema in `supabase/migrations/0001_init.sql` is final for the MVP | Prevents agent drift |
| D13 | One perk per capture. Bulk import is later | Keeps extraction and the confirm UI simple |

## What this replaces from earlier planning

- Earlier notes mentioned email and Discord channels, quiet hours, a screenshot storage step with cleanup, and stored `expiring` and `expired` statuses. These are all replaced by the decisions above.

## Open items

1. Exact Gemma 4 model ID, image limits and rate limits: look up in the Gemini API docs (agent task 2.1).
2. Whether the "ask" box ships in the first demo: it is Phase 4 and optional.

## Agent decisions

Agents append here: date, task ID, the decision, and why. Keep entries to two lines.

(none yet)
