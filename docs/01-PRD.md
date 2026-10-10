# 01. Product Requirements

## Problem

Students and developers claim many credits and perks (cloud credits, AI API grants, hackathon prizes, student packs, trials). Each lives in a different dashboard or email and expires on its own date. People forget them and notice only after they expire. Logging each one by hand is a chore, so spreadsheets and calendar reminders get abandoned.

## Solution

Perkwatch stores every perk with its expiry and restrictions, reminds the owner on Telegram on an escalating schedule, and removes the data-entry chore: upload a screenshot or paste an email, Gemma 4 extracts the details, the owner confirms, and the perk is tracked.

## Users

Single owner (a student or developer). No other users in the MVP.

## Goals

- No perk is lost because it was forgotten.
- Capturing a perk takes under 30 seconds.
- Extracted data is accurate or clearly flagged as uncertain.

## Non-goals (MVP)

- Team workspaces or multiple users
- Email, Discord or push notifications
- Scraping provider dashboards or storing provider logins
- Payments, billing, native mobile apps
- Storing screenshots
- Bulk import, email forwarding, browser extension, calendar feed

## Functional requirements

Priority: M = MVP, O = optional demo feature in the MVP, L = later (see `10-ROADMAP.md`).

| ID | Requirement | Priority |
| --- | --- | --- |
| F1 | Sign in as the single owner by magic link; any other email is rejected | M |
| F2 | Upload a screenshot (PNG, JPEG, WebP) or paste email text to start a capture | M |
| F3 | Gemma 4 extracts platform, type, amount, currency, expires_at, claim_by, expiry_note, restrictions, confidence | M |
| F4 | Confirmation screen shows the extracted fields beside the source image or text. The owner edits and approves before saving | M |
| F5 | Manual entry form with the same fields | M |
| F6 | Dashboard sorted by expiry (soonest first, no-date last), with status, days left, and a summary of value expiring in 30 days | M |
| F7 | Lifecycle statuses: eligible, claimed, active, used, archived, with computed expiring, expired, missed | M |
| F8 | Edit a perk, mark as used, archive, delete | M |
| F9 | Reminders at 30, 14, 7, 3, 1 days before `expires_at`, and before `claim_by` for eligible perks | M |
| F10 | Telegram bot delivers reminders | M |
| F11 | Settings: link and unlink Telegram, choose thresholds, set timezone | M |
| F12 | Telegram `/expiring` lists perks expiring in the next 30 days. `/help` lists commands | M |
| F13 | Warn about possible duplicates when saving (same platform, amount and expiry) | M |
| F14 | Ask box: natural-language questions answered only from the owner's stored perks | O |
| F15 | Weekly digest, student verification tracking, calendar feed, email forwarding, bulk import | L |

## Non-functional requirements

| Area | Requirement |
| --- | --- |
| Reliability | Reminders run from a scheduler independent of the web UI. Failed sends retry up to 3 times across runs. No duplicates, ever |
| Accuracy | Dates validated by code. Low-confidence or missing fields highlighted in the confirm UI |
| Security | RLS on all tables. Secrets server-only. Webhook and cron endpoints authenticated. See `07-SECURITY-PRIVACY.md` |
| Privacy | Images never stored. Only extracted fields are saved. Logs contain no personal content |
| Performance | Extraction returns in about 10 seconds. Dashboard renders in under 2 seconds for 300 perks |
| Cost | Fit in free tiers. Cap AI calls per day (`AI_DAILY_LIMIT`, default 30) |
| Accessibility | Keyboard navigable, sufficient contrast, status never conveyed by color alone |
| Observability | Structured server logs for extraction failures, cron runs and send failures |

## Perk fields

| Field | Type | Notes |
| --- | --- | --- |
| platform | text, required | "AWS Activate", "GitHub Student Pack" |
| type | enum | credit, trial, license, verification, offer, other |
| status | enum | eligible, claimed, active, used, archived |
| amount | number, optional | Non-negative |
| currency | text, optional | ISO 4217, uppercase (USD) |
| claim_by | date, optional | Deadline to claim an eligible offer |
| expires_at | date, optional | No date means no reminders |
| expiry_note | text, optional | Raw expiry wording when no exact date exists ("12 months after activation") |
| restrictions | text, optional | What it can and cannot be used for |
| notes | text, optional | Free notes |
| ai_confidence | high, medium, low, or null | Null when entered manually |

## User flows

### Capture

1. Owner opens Add, drops a screenshot or pastes text.
2. The browser downscales the image, then posts it to `/api/extract`.
3. The server validates, rate limits, calls Gemma 4, validates the JSON, and returns a proposal with warnings.
4. The owner reviews highlighted fields next to the source, edits, and saves.
5. A server action writes the perk. Nothing else is stored.

### Reminder

1. The daily cron calls `/api/cron/remind`.
2. For each perk, the engine decides whether a threshold is due and queues one notification row (unique per perk, kind, threshold, channel).
3. Pending and retryable rows are sent through the Telegram bot and marked sent or failed.

### Link Telegram

1. Owner opens Settings and presses "Link Telegram". The app shows a deep link with a one-time code (valid 10 minutes).
2. Owner opens it in Telegram and presses Start.
3. The webhook matches the code, stores the chat id and replies "Linked".

## Success metrics

- Median capture time under 30 seconds
- At least 90 percent correct `expires_at` on clear screenshots in the evaluation set, the rest flagged low confidence
- 100 percent of due reminders either sent or logged as failed with a reason
- Number of perks saved that would otherwise have expired unnoticed (the demo number)
