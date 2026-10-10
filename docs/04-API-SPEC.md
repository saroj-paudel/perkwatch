# 04. API and Actions Spec

Conventions

- JSON in, JSON out, unless noted. Dates are `YYYY-MM-DD` strings.
- Errors use one shape: `{ "error": { "code": "STRING", "message": "Human readable" } }` with the HTTP status shown below.
- All route handlers validate input with zod. Never echo raw exceptions.
- Perk and settings mutations are **Server Actions** (user session, RLS). External-facing endpoints are **route handlers**.

## Error codes

| Code | HTTP | Meaning |
| --- | --- | --- |
| `UNAUTHENTICATED` | 401 | No valid session, secret or header |
| `FORBIDDEN` | 403 | Signed in but not the owner |
| `VALIDATION_ERROR` | 400 | Input failed validation (message lists the first problem) |
| `UNSUPPORTED_MEDIA` | 415 | File type not PNG, JPEG or WebP |
| `PAYLOAD_TOO_LARGE` | 413 | Image over 4 MB or text over 20,000 characters |
| `AI_RATE_LIMITED` | 429 | Daily limit reached or the model returned 429 |
| `EXTRACTION_FAILED` | 502 | Model call failed or output unusable after one repair attempt |
| `NOT_FOUND` | 404 | Perk or resource not found |
| `INTERNAL` | 500 | Unexpected error (logged server-side) |

## Route handlers

### POST `/api/extract`

Auth: owner session. Returns a **proposal only**. Saves nothing.

Request: `multipart/form-data` with **one** of

- `file`: PNG, JPEG or WebP, 4 MB or less
- `text`: pasted email or page text, 20,000 characters or less

Response 200:

```json
{
  "extraction": {
    "platform": "AWS Activate",
    "type": "credit",
    "amount": 500,
    "currency": "USD",
    "expires_at": "2026-12-31",
    "claim_by": null,
    "expiry_note": "Expires Dec 31, 2026",
    "restrictions": "Not valid for Marketplace purchases",
    "confidence": "high"
  },
  "warnings": [
    { "field": "expires_at", "code": "DATE_IN_PAST", "message": "This date is already past." }
  ]
}
```

Warning codes: `DATE_IN_PAST`, `DATE_FAR_FUTURE` (more than 5 years), `DATE_MISSING`, `LOW_CONFIDENCE`, `AMBIGUOUS_DATE`, `PLATFORM_MISSING`.

Steps: authenticate, validate, call RPC `increment_ai_usage(user_id, AI_DAILY_LIMIT)` via the admin client (reject with `AI_RATE_LIMITED` if false), call the model, parse and validate, return. See `05-AI-EXTRACTION.md`.

### POST `/api/ask` (Phase 4, optional)

Auth: owner session. Counts toward `AI_DAILY_LIMIT`.

Request: `{ "question": "string, 1 to 500 characters" }`

Response 200: `{ "answer": "plain text" }`

Rules: load the owner's non-archived perks (max 200), send them as JSON context, instruct the model to answer only from that data and to say when the data does not cover the question. The client renders `answer` as plain text.

### POST `/api/telegram/webhook`

Auth: header `X-Telegram-Bot-Api-Secret-Token` must equal `TELEGRAM_WEBHOOK_SECRET`, otherwise 401. Service-role client.

Body: a Telegram Update object (validate only the fields used: `message.chat.id`, `message.text`).

Behavior (always respond 200 `{ "ok": true }` after handling, except auth failure):

| Message | Action |
| --- | --- |
| `/start <code>` with a valid unexpired code | Store `telegram_chat_id`, clear the code, reply "Linked. You will get reminders here." |
| `/start` without a valid code | Reply with instructions to use "Link Telegram" in Settings |
| `/expiring` from a linked chat | Reply with up to 10 perks expiring in the next 30 days |
| `/expiring` from an unlinked chat | Reply "This chat is not linked." |
| `/help` | Reply with the command list |
| anything else | Ignore |

See `06-NOTIFICATIONS.md` for message formats.

### GET and POST `/api/cron/remind`

Auth: header `Authorization: Bearer <CRON_SECRET>`, otherwise 401. Both methods accepted (Vercel Cron uses GET).

Response 200:

```json
{ "users": 1, "perks_checked": 42, "queued": 3, "sent": 3, "failed": 0 }
```

Algorithm: `06-NOTIFICATIONS.md`.

### GET `/auth/callback`

Exchanges the Supabase auth code for a session, then redirects to `/`. On error redirects to `/login?error=1`.

## Server Actions

All actions verify the owner session, validate with zod, and return `{ ok: true, data }` or `{ ok: false, error: { code, message } }`. After a successful mutation they call `revalidatePath("/")`.

### `src/app/actions/perks.ts`

| Action | Input | Notes |
| --- | --- | --- |
| `createPerk` | Perk fields (see below) | `user_id` comes from the session, never from input. Returns the perk and a `duplicates` array (see F13) |
| `updatePerk` | `{ id, ...fields }` | Date or status changes reset reminders through the database trigger |
| `setPerkStatus` | `{ id, status }` | One of the stored statuses |
| `deletePerk` | `{ id }` | Cascades to notifications |

Perk fields input schema (`lib/perks/schema.ts`):

| Field | Rule |
| --- | --- |
| `platform` | string, trimmed, 1 to 80 |
| `type` | one of credit, trial, license, verification, offer, other |
| `status` | one of eligible, claimed, active, used, archived (default active) |
| `amount` | number 0 or more, or null |
| `currency` | three uppercase letters, or null. Required if `amount` is set |
| `claim_by`, `expires_at` | valid `YYYY-MM-DD` or null |
| `expiry_note` | string up to 500, or null |
| `restrictions`, `notes` | string up to 2000, or null |
| `ai_confidence` | high, medium, low, or null |

Duplicate check (`lib/perks/duplicates.ts`): same user, same platform (case-insensitive), same `expires_at`, same `amount`, status not archived. Returned as a warning, never blocks saving.

### `src/app/actions/settings.ts`

| Action | Input | Notes |
| --- | --- | --- |
| `updateSettings` | `{ thresholds: number[], timezone: string, telegram_enabled: boolean }` | thresholds: unique integers 1 to 365, sorted descending, 1 to 10 items. timezone: must be accepted by `Intl.DateTimeFormat` |
| `createTelegramLink` | none | Generates a 10 character code from `crypto.randomBytes` (letters and digits), expiry now plus 10 minutes. Returns `{ code, deepLink, expiresAt }` where `deepLink = https://t.me/<TELEGRAM_BOT_USERNAME>?start=<code>` |
| `unlinkTelegram` | none | Clears chat id, code and expiry |

## Pages (UI routes)

| Route | Purpose |
| --- | --- |
| `/login` | Email field, sends magic link |
| `/` | Dashboard |
| `/add` | Capture and confirm |
| `/perks/[id]` | View and edit one perk |
| `/settings` | Telegram link, thresholds, timezone |
| `/ask` | Ask box (Phase 4) |

### Dashboard rules

- Default sort: `expires_at` ascending, nulls last. Archived hidden by default.
- Tabs: All (not archived), Expiring, Eligible, Active, Used, Expired, Archived.
- Summary strip: number expiring within 30 days, and their value grouped by currency.
- Each row: platform, type, amount and currency, expiry date and days left, status badge (text label plus color), actions (edit, mark used, archive, delete with confirm).
- Status badges always include text, never color alone.

### Add page rules

- Two inputs: drop or choose an image, or paste text. Image is downscaled in the browser (long edge 1600 px, JPEG quality 0.85) before upload.
- While extracting: show progress and allow cancel.
- On success: form pre-filled, with the source image or text visible beside it. Fields that are null or tied to a warning are highlighted. A banner lists the warnings.
- If `expires_at` is empty on a credit or trial, show "No reminders without an expiry date."
- Save is disabled while `platform` is empty or validation fails.
- On `EXTRACTION_FAILED` or `AI_RATE_LIMITED`: show the message and offer the manual form.
