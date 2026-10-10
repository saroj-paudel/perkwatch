# 08. Testing

Tooling: Vitest for unit tests. A local or throwaway Supabase project for the RLS check. Real-model checks only through `npm run eval:extract`.

## Unit tests (required, no network)

| Area | File | Cases |
| --- | --- | --- |
| Dates | `tests/dates.test.ts` | `todayInTz` for UTC and a UTC+5:45 zone around midnight, `daysBetween` across month and year boundaries and leap day, invalid dates rejected |
| Status | `tests/status.test.ts` | Every row of the display status table in `03-DATA-MODEL.md`, including no-date perks, today as expiry (expiring, not expired), yesterday as expiry (expired), eligible with past `claim_by` (missed) |
| Reminder buckets | `tests/reminders.test.ts` | Every row of the table in `06-NOTIFICATIONS.md`, custom thresholds, unsorted thresholds, single threshold |
| Reminder run | `tests/reminders-run.test.ts` | With an in-memory fake store: sends once per bucket, second run sends nothing, catch-up for a late-added perk, date edit resets and re-sends, used and archived skipped, claim reminders for eligible, more than 5 due becomes one combined message |
| Extraction parsing | `tests/json.test.ts`, `tests/extract.test.ts` | Fenced JSON, JSON with prose around it, braces inside strings, trailing commas fail then repair, numeric strings and currency symbols normalized, bad dates rejected, repair path called once, second failure gives `EXTRACTION_FAILED` (mock the model) |
| Warnings | `tests/warnings.test.ts` | Each warning code |
| Perk schema | `tests/perk-schema.test.ts` | Currency required with amount, bounds, trimming, impossible dates like 2026-02-30 |
| Duplicates | `tests/duplicates.test.ts` | Case-insensitive platform, null amount handling, archived ignored |
| Telegram format | `tests/format.test.ts` | HTML escaping of `<`, `>`, `&`, singular "1 day", "today", truncation, urgent icon at thresholds 3 and 1, combined message with "and N more" |
| Env | `tests/env.test.ts` | Missing required variable fails with a clear message |

Pure logic must have no dependency on Next.js, Supabase or `fetch`, so tests stay fast. Inject the clock (`now`) and the store.

## Route tests (mock external services)

- `/api/extract`: 401 without session, 415 wrong type, 413 too large, 429 when the RPC returns false, 200 with a proposal when the model mock returns valid JSON, 502 when the mock returns garbage twice. Nothing is written to the database in any case.
- `/api/telegram/webhook`: 401 without the secret header, link success, expired code, unknown code, `/expiring` linked and unlinked, unknown text ignored.
- `/api/cron/remind`: 401 without the bearer token, correct summary JSON, one failing send does not stop the run.

## RLS and database checks (manual script or Supabase local)

1. Create two users, A and B.
2. As A, insert a perk. As B, `select` returns zero rows and update or delete affects zero rows.
3. As B, inserting a perk with `user_id` of A is rejected.
4. As A, `select` from `notifications` works but inserting is rejected.
5. As A, calling `increment_ai_usage` through the API is rejected (execute revoked).
6. Updating a perk's `expires_at` deletes its notification rows. Deleting the perk cascades.

## AI evaluation (needs real keys)

`npm run eval:extract`. See `05-AI-EXTRACTION.md`. Record the result table in `docs/eval-results.md` after each prompt or model change (date, model id, per-field accuracy).

## Manual QA checklist

Run before calling the MVP done, on desktop and a phone-width viewport.

Auth

- [ ] Magic link signs in the owner
- [ ] A different email gets no account and no access
- [ ] Signing out then opening `/` redirects to `/login`

Capture

- [ ] PNG, JPEG and WebP screenshots extract
- [ ] A non-image file shows a clear error
- [ ] Pasted email text extracts
- [ ] Ambiguous date shows a warning and an empty date field
- [ ] Past date shows a warning
- [ ] Low-confidence fields are highlighted
- [ ] Extraction failure offers the manual form
- [ ] Duplicate warning appears on a second identical save
- [ ] Image never appears in network requests after save, and nothing is stored

Dashboard

- [ ] Sorted by expiry, no-date perks last
- [ ] Tabs filter correctly
- [ ] Summary groups value by currency and never adds different currencies
- [ ] Mark used, archive, edit and delete work
- [ ] Status badges have text, not just color
- [ ] Usable with keyboard only

Telegram

- [ ] Link flow works and the code cannot be reused
- [ ] Expired code is rejected
- [ ] Triggering the cron manually sends the right reminders
- [ ] Triggering it again sends nothing
- [ ] Changing an expiry date and re-running sends a fresh reminder
- [ ] `/expiring` and `/help` work
- [ ] Unlink stops reminders

Deployment

- [ ] Cron fires on schedule (check the host's cron log)
- [ ] Webhook returns 401 for a request without the header
- [ ] Environment variables are present in production and none are exposed to the browser
