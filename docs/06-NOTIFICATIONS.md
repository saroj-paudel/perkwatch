# 06. Notifications (Telegram)

## Channel

Telegram Bot API over plain `fetch` (`lib/notify/telegram.ts`). No Telegram library. Base URL: `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/<method>`. Verify method and field names against the official Bot API docs.

Functions to implement:

```ts
sendTelegramMessage(chatId: number, html: string): Promise<{ ok: true } | { ok: false; error: string }>
```

Use `sendMessage` with `parse_mode: 'HTML'` and `disable_web_page_preview: true`. Escape `&`, `<`, `>` in all user-supplied text (`lib/notify/format.ts: escapeHtml`). A failed response, a network error, or a non-200 status is a failure with a short error string (never include the token).

## Linking flow

1. Settings page calls `createTelegramLink`. It stores a one-time code (10 characters, letters and digits, from `crypto.randomBytes`) and `telegram_link_expires_at = now + 10 minutes`. The UI shows `https://t.me/<TELEGRAM_BOT_USERNAME>?start=<code>` as a button.
2. The owner opens it in Telegram and presses Start. Telegram sends `/start <code>` to the webhook.
3. The webhook finds the settings row with that code and a non-expired timestamp, sets `telegram_chat_id`, clears the code and expiry, and replies "Linked. You will get reminders here."
4. If the chat id is already linked to another user, or the code is invalid or expired, reply with instructions to generate a new link. Do not reveal which case happened.
5. Unlink clears `telegram_chat_id`. Reminders stop.

Setting the webhook: `scripts/set-telegram-webhook.ts` (also `npm run telegram:webhook`) calls `setWebhook` with `url = APP_URL + '/api/telegram/webhook'` and `secret_token = TELEGRAM_WEBHOOK_SECRET`. The webhook route rejects any request whose `X-Telegram-Bot-Api-Secret-Token` header does not match.

## Reminder engine (`lib/notify/reminders.ts`)

### Pure functions (unit tested, no I/O)

```ts
todayInTz(tz: string, now?: Date): string          // 'YYYY-MM-DD' in that timezone
daysBetween(fromISO: string, toISO: string): number // calendar days, UTC date math on YYYY-MM-DD
reminderBucket(daysLeft: number, thresholds: number[]): number | null
```

`reminderBucket` returns the **smallest threshold that is greater than or equal to `daysLeft`**, or `null` when `daysLeft` is negative or greater than the largest threshold. A value of `0` (expires today) maps to the smallest threshold.

| daysLeft | thresholds 30,14,7,3,1 | Result |
| --- | --- | --- |
| 45 | | null |
| 30 | | 30 |
| 29 | | 30 |
| 15 | | 30 |
| 14 | | 14 |
| 8 | | 14 |
| 7 | | 7 |
| 5 | | 7 |
| 3 | | 3 |
| 2 | | 3 |
| 1 | | 1 |
| 0 | | 1 |
| -1 | | null |

Because of the unique key `(perk_id, kind, threshold, channel)`, a bucket sends at most once. A perk added with 5 days left sends once for bucket 7 (catch-up), then again at 3 and 1. A missed cron day is covered automatically.

### Run algorithm (`GET|POST /api/cron/remind`, admin client)

1. Verify `Authorization: Bearer <CRON_SECRET>`.
2. Load `notification_settings` rows where `telegram_enabled` is true and `telegram_chat_id` is not null.
3. For each user:
   1. `today = todayInTz(settings.timezone)`.
   2. Load that user's perks:
      - kind `expiry`: status in (`claimed`, `active`) and `expires_at` not null
      - kind `claim`: status = `eligible` and `claim_by` not null
   3. For each perk: `daysLeft = daysBetween(today, date)`. `bucket = reminderBucket(daysLeft, settings.thresholds)`. If `bucket` is not null, insert a notification row (status `pending`) with "on conflict do nothing".
   4. Load this user's notifications with status `pending`, or `failed` with `attempts < 3`, joined to their perks.
   5. Send:
      - If **5 or fewer** are due: send one message each, ordered by days left ascending, with about 1.1 seconds between messages to the same chat.
      - If **more than 5** are due: send **one combined message** listing them (soonest first, max 15 lines, then "and N more"). Mark every included row on success.
   6. On success set `status = 'sent'`, `sent_at = now()`. On failure set `status = 'failed'`, `attempts = attempts + 1`, `error = <short message>`.
4. Return the summary JSON `{ users, perks_checked, queued, sent, failed }`.

The run is idempotent: calling it twice in one day sends nothing new.

Never send for perks whose date is already past (`daysLeft < 0`), or for statuses `used` or `archived`.

## Message formats (`lib/notify/format.ts`)

Single expiry reminder (HTML):

```text
⏰ <b>AWS Activate</b> credit expires in <b>7 days</b> (2026-12-31)
Amount: 500 USD
Restrictions: Not valid for Marketplace purchases
<APP_URL>/perks/<id>
```

Rules:

- "in N days" becomes "in 1 day" for 1 and "today" for 0.
- Omit the Amount line when amount is null. Omit Restrictions when null. Truncate restrictions to 200 characters with an ellipsis.
- Urgent (threshold 3 or 1): start with `🚨` instead of `⏰`.
- Claim reminder: `📝 <b>GitHub Student Pack</b> offer is still unclaimed. Claim by 2026-11-20 (in 7 days)`.
- Combined message: a header line `You have N perks needing attention:` followed by one line per perk `• <b>Platform</b>: expires in N days (date)`.

`/expiring` reply: header `Expiring in the next 30 days:` then up to 10 lines `• <b>Platform</b>: N days (date)`, soonest first. If none: `Nothing expiring in the next 30 days.`

`/help` reply: `Commands: /expiring lists perks expiring in 30 days. /help shows this message.`

## Failure handling

- A Telegram error that indicates the bot was blocked or the chat does not exist (HTTP 403 or 400) marks the row failed and, after 3 attempts, stops retrying. Do not unlink automatically. Log the event with the user id.
- The cron route never throws on a single user's failure. It processes the next user and counts the failure in the summary.
