# 03. Data Model

The executable schema is `supabase/migrations/0001_init.sql`. It is final for the MVP. Do not alter it without recording a decision. This file explains it.

## Tables

| Table | Purpose | Written by |
| --- | --- | --- |
| `perks` | Every credit, trial, license, offer | Owner (server actions, user session) |
| `notification_settings` | One row per user: Telegram link, thresholds, timezone | Owner (server actions), webhook (service role) for linking |
| `notifications` | One row per reminder due, with send status | Cron route (service role) |
| `ai_usage` | Daily count of AI calls for rate limiting | `increment_ai_usage` RPC (service role) |

No storage bucket exists. Images are never stored.

## Stored vs computed status

Stored `status` is one of `eligible`, `claimed`, `active`, `used`, `archived`. The following are **computed** in `lib/perks/status.ts` from stored status, dates and "today in the owner's timezone":

| Display status | Rule (first match wins) |
| --- | --- |
| `used` | stored `used` |
| `archived` | stored `archived` |
| `missed` | stored `eligible` and `claim_by` is before today |
| `eligible` | stored `eligible` |
| `expired` | stored `claimed` or `active`, and `expires_at` is before today |
| `expiring` | stored `claimed` or `active`, and `expires_at` is within the next 30 days (today included) |
| `claimed` / `active` | otherwise, the stored value |

A perk with no `expires_at` never becomes `expiring` or `expired` and never gets expiry reminders.

## Reminder rows

- `kind = 'expiry'` is for perks with status `claimed` or `active` and a non-null `expires_at`.
- `kind = 'claim'` is for perks with status `eligible` and a non-null `claim_by`.
- `threshold` is the day bucket that triggered it (30, 14, 7, 3, 1 by default).
- The unique key `(perk_id, kind, threshold, channel)` guarantees at most one message per bucket. Inserts use "on conflict do nothing".
- Changing `expires_at`, `claim_by` or `status` on a perk deletes that perk's notification rows (trigger `perks_reset_notifications`), so reminders recompute.
- Deleting a perk cascades to its notifications.

## Telegram linking fields

| Column | Meaning |
| --- | --- |
| `telegram_link_code` | One-time code, 10 characters, unique while set |
| `telegram_link_expires_at` | Code expiry, 10 minutes after creation |
| `telegram_chat_id` | Set by the webhook when the owner presses Start with a valid code. Unique |
| `telegram_enabled` | Owner switch to pause reminders without unlinking |

## Row-level security summary

| Table | Owner can | Service role |
| --- | --- | --- |
| `perks` | select, insert, update, delete own rows | bypasses RLS |
| `notification_settings` | select, insert, update own row | bypasses RLS |
| `notifications` | select own rows | insert, update |
| `ai_usage` | nothing | everything (via RPC) |

## Data rules enforced by the database

- `platform`: 1 to 80 characters
- `amount`: null or 0 or more, two decimals
- `currency`: null or three uppercase letters
- `restrictions`, `notes`: up to 2000 characters. `expiry_note`: up to 500
- `thresholds`: 1 to 10 integers

The application also validates these with zod in `lib/perks/schema.ts`, so users see friendly errors before the database rejects anything.

## Money

Never add amounts across currencies. The dashboard summary groups totals by currency (for example "USD 400, INR 5000").

## Deletion

"Delete account data" is out of the MVP UI. For the single owner, deleting the auth user in the Supabase dashboard cascades to every table.
