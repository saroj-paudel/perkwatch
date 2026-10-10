# 09. Build Plan

Execute in order. One task at a time. After every task: run `npm run lint`, `npm run typecheck`, `npm test`, check the acceptance criteria, commit with the task ID. Stop after each phase and report.

Rules that apply to every task are in `AGENTS.md`.

---

## Phase 0: Foundation

### Task 0.1: Scaffold

- Create the Next.js app in the repo root with TypeScript, Tailwind, ESLint, App Router, `src/` directory, import alias `@/*`.
- Install only the dependencies listed in `docs/02-ARCHITECTURE.md`.
- Add scripts: `typecheck` (`tsc --noEmit`), `test` (`vitest run`), `eval:extract`, `telegram:webhook` (both via `tsx scripts/...`). Create the `scripts/` files as stubs that print "not implemented".
- Add `.gitignore` entries: `.env.local`, `.env*.local`, `node_modules`, `.next`.
- Add `vercel.json` with the daily cron from the architecture doc.

Acceptance:

- [ ] `npm run dev` serves a placeholder home page
- [ ] `npm run lint`, `npm run typecheck`, `npm test` all pass (add one trivial test so Vitest exits 0)
- [ ] `.env.example` is present and `.env.local` is git-ignored

### Task 0.2: Environment validation

- Implement `lib/env.ts` with zod: a server schema (all variables in `.env.example`) and a public schema (`NEXT_PUBLIC_*`). Export typed `env` (server) and `publicEnv`.
- `AI_DAILY_LIMIT` defaults to 30 and is coerced to a number. `GEMMA_MODEL_ID` is required for AI routes only (validate lazily in `lib/ai/gemma.ts`, so the app still runs without it).

Acceptance:

- [ ] Missing `SUPABASE_SERVICE_ROLE_KEY` produces a clear error naming the variable
- [ ] `tests/env.test.ts` passes

### Task 0.3: Supabase clients and auth

- Implement `lib/supabase/{server,client,admin,middleware}.ts` following the current `@supabase/ssr` guidance for the installed Next.js version. `admin.ts` starts with `import 'server-only'`.
- `src/middleware.ts`: refresh session, redirect unauthenticated users to `/login`, allow `/login`, `/auth/callback`, `/api/telegram/webhook`, `/api/cron/remind` and static assets.
- `/login` page: email field, calls `signInWithOtp` with `shouldCreateUser: false`, shows "Check your email".
- `/auth/callback` route: exchange the code, redirect to `/`.
- `(app)/layout.tsx`: get user with `getUser()`, if `user.email !== OWNER_EMAIL` sign out and redirect to `/login`. Include a simple nav (Dashboard, Add, Settings) and sign out.
- Apply `supabase/migrations/0001_init.sql` to the Supabase project (document this in the README, it is already there).

Acceptance:

- [ ] Owner can sign in by magic link and see the empty dashboard
- [ ] Visiting `/` signed out redirects to `/login`
- [ ] A non-owner email cannot get in
- [ ] Service-role key does not appear in `.next/static` (grep the build)

**Phase 0 report, then continue.**

---

## Phase 1: Perks without AI

### Task 1.1: Date and status logic (pure, tested)

- Implement `lib/perks/dates.ts` (`todayInTz`, `daysBetween`, `isRealCalendarDate`, `addDays` if needed) and `lib/perks/status.ts` (`displayStatus`) exactly as specified in `03-DATA-MODEL.md` and `06-NOTIFICATIONS.md`.
- Write the tests listed for Dates and Status in `08-TESTING.md`.

Acceptance:

- [ ] Every row in the status table has a test
- [ ] `todayInTz('Asia/Kathmandu', new Date('2026-01-01T19:00:00Z'))` returns `2026-01-02`
- [ ] 2026-02-30 is rejected by `isRealCalendarDate`

### Task 1.2: Perk schema and server actions

- `lib/perks/schema.ts` (zod, per `04-API-SPEC.md`), `lib/perks/duplicates.ts`, `lib/perks/queries.ts` (list, get).
- `app/actions/perks.ts`: `createPerk`, `updatePerk`, `setPerkStatus`, `deletePerk`. User id comes from the session. Return the `{ ok, data | error }` shape.
- Tests: Perk schema and Duplicates from `08-TESTING.md`.

Acceptance:

- [ ] Invalid input returns `VALIDATION_ERROR` with a helpful message
- [ ] Saving an identical perk twice returns a `duplicates` array but still saves
- [ ] Unit tests pass

### Task 1.3: Dashboard and perk form

- `(app)/page.tsx`: summary strip, tabs, sorted table per `04-API-SPEC.md` dashboard rules. Server component reading through the user-session client. Empty state with a link to Add.
- `components/PerkForm.tsx`: all fields, client-side validation using the same zod schema, used for manual add (`/add` when no extraction yet, tab "Enter manually") and edit (`/perks/[id]`).
- Row actions: edit, mark used, archive, delete with a confirm dialog.
- Status badge component: text label plus color.

Acceptance:

- [ ] Add a perk manually and see it on the dashboard in the right order
- [ ] No-date perks sort last
- [ ] Summary groups values by currency
- [ ] Edit, mark used, archive, delete all work and the list updates
- [ ] Keyboard-only use works for the form and row actions

**Phase 1 report, then continue.**

---

## Phase 2: AI extraction

### Task 2.1: Model client (verify first)

- Look up the exact Gemma 4 model ID and the current `@google/genai` usage in the Gemini API docs. Record the model ID in the README quick start and note anything surprising (JSON mode, system instruction support, image limits) under "Agent decisions" in `00-DECISIONS.md`.
- Implement `lib/ai/gemma.ts` (`callModel(parts)` with a 25 second timeout and error mapping) per `05-AI-EXTRACTION.md`.
- Add a throwaway script or test (not committed) to confirm a real call works with a text-only prompt.

Acceptance:

- [ ] A real text prompt returns text from Gemma 4
- [ ] Timeout and 429 map to the right error codes in a unit test with a mocked SDK
- [ ] `GEMMA_MODEL_ID` is read from the environment, not hard-coded

### Task 2.2: Parsing, validation, warnings

- Implement `lib/ai/schemas.ts`, `lib/ai/json.ts`, `lib/ai/prompts.ts`, `lib/ai/extract.ts` including the repair attempt and `lib/perks`-level warning generation exactly as in `05-AI-EXTRACTION.md`.
- Tests: Extraction parsing and Warnings from `08-TESTING.md`, with the model mocked.

Acceptance:

- [ ] All parsing cases pass, including braces inside strings
- [ ] Exactly one repair call is made on failure, never more
- [ ] Every warning code has a test

### Task 2.3: `/api/extract`

- Implement the route per `04-API-SPEC.md`: auth, multipart parsing, MIME allow-list with magic-byte check (PNG, JPEG, WebP), size limits, rate limit through the admin client RPC, call extraction, return proposal. Nothing is saved.
- Route tests per `08-TESTING.md`.

Acceptance:

- [ ] 401, 413, 415, 429, 502 and 200 paths all tested
- [ ] No file is written to disk or storage (grep for `fs`, `writeFile`, `.storage`)
- [ ] Logs contain no image bytes, text or model output

### Task 2.4: Add page (capture and confirm)

- `(app)/add/page.tsx`: tabs "Screenshot", "Paste text", "Enter manually".
- Browser downscale (canvas, long edge 1600 px, JPEG 0.85, must be under 4 MB).
- Progress state with cancel, error states for `EXTRACTION_FAILED` and `AI_RATE_LIMITED` with a manual fallback.
- After extraction: pre-filled `PerkForm` with the source image (object URL) or text beside it, highlighted uncertain fields, warnings banner, duplicate warning on save.
- Privacy sentence per `07-SECURITY-PRIVACY.md`.

Acceptance:

- [ ] End to end: drop a screenshot, review, save, see it on the dashboard
- [ ] Ambiguous or past dates are visibly flagged
- [ ] Nothing is saved until the owner presses Save
- [ ] Works at phone width

### Task 2.5: Evaluation harness

- `eval/cases.json` with at least 30 cases (including the tricky ones listed in `05-AI-EXTRACTION.md`) and `scripts/eval-extract.ts` printing per-field accuracy, `expires_at` accuracy separately, and failures.
- Record the first run in `docs/eval-results.md`.

Acceptance:

- [ ] `npm run eval:extract` runs and prints a summary table
- [ ] Fixtures contain no real personal data

**Phase 2 report, then continue.**

---

## Phase 3: Telegram and reminders

### Task 3.1: Telegram client and formatting

- `lib/notify/telegram.ts` (`sendTelegramMessage`), `lib/notify/format.ts` (`escapeHtml`, single, claim, combined and `/expiring` messages) per `06-NOTIFICATIONS.md`.
- Tests: Telegram format.

Acceptance:

- [ ] HTML in a platform name is escaped in every message type
- [ ] "1 day", "today", urgent icon and "and N more" all tested
- [ ] Token never appears in an error message (test)

### Task 3.2: Settings page and linking

- `app/actions/settings.ts`: `updateSettings`, `createTelegramLink`, `unlinkTelegram`.
- `(app)/settings/page.tsx`: link status, "Link Telegram" button showing the deep link and countdown, unlink, enable switch, thresholds editor, timezone select (default to the browser's timezone).
- `lib/notify/link.ts` for code generation.

Acceptance:

- [ ] Code is 10 characters from `crypto.randomBytes`, expires in 10 minutes
- [ ] Invalid thresholds and timezones are rejected with clear messages
- [ ] Settings persist

### Task 3.3: Webhook

- `/api/telegram/webhook` per `04-API-SPEC.md` with constant-time secret comparison.
- `scripts/set-telegram-webhook.ts`.
- Route tests.

Acceptance:

- [ ] 401 without the secret header
- [ ] Link success, expired code, unknown code, `/expiring`, `/help` all behave per spec
- [ ] After linking in a real Telegram chat, the settings page shows "Linked"

### Task 3.4: Reminder engine and cron route

- Pure functions and the run algorithm per `06-NOTIFICATIONS.md`, with an injectable clock and store.
- `/api/cron/remind` with bearer secret, constant-time compare, summary JSON.
- Tests: Reminder buckets and Reminder run.

Acceptance:

- [ ] All reminder tests pass, including idempotency and catch-up
- [ ] Manual run (curl with the bearer token) sends the right messages to the owner's Telegram
- [ ] Second manual run sends nothing
- [ ] Editing an expiry date then re-running sends a fresh reminder

**Phase 3 report, then continue.**

---

## Phase 4: Ask box (optional demo feature)

### Task 4.1: `/api/ask` and page

- `lib/ai/ask.ts` and the route per `05-AI-EXTRACTION.md` and `04-API-SPEC.md`. Compute `days_left` and display status in code and pass them in.
- `(app)/ask/page.tsx`: input, example questions as buttons ("What expires in the next 30 days?", "Can I use my cloud credits for GPU instances?"), plain-text answer, loading and error states.

Acceptance:

- [ ] Answers cite the platform they used
- [ ] A question the data cannot answer gets "I can't tell from your saved perks"
- [ ] Output is rendered as plain text
- [ ] Counts toward the daily AI limit

---

## Phase 5: Polish and release

### Task 5.1: UX polish

- Loading, empty and error states on every page. Toasts for save, delete and errors. Consistent spacing and a readable table on mobile (cards or horizontal scroll).
- Landing copy on the dashboard empty state explaining the three-step flow.

Acceptance:

- [ ] No page shows a blank screen on error
- [ ] Layout works at 375 px width

### Task 5.2: Hardening

- Security headers in `next.config`.
- Confirm every item in the pre-release checklist in `07-SECURITY-PRIVACY.md`.
- Run the RLS checks in `08-TESTING.md`.

Acceptance:

- [ ] Security checklist fully ticked
- [ ] RLS checks pass with two users

### Task 5.3: Release

- Deploy, set environment variables, register the Telegram webhook, confirm cron runs.
- Run the manual QA checklist in `08-TESTING.md`.
- Finalize the README (real setup steps verified end to end, screenshots optional).
- Prepare a 2 minute demo script: import 3 real perks, show Telegram reminder, show the ask box, state the number of perks saved from expiry.

Acceptance:

- [ ] Manual QA checklist ticked
- [ ] A reminder arrives in Telegram from the deployed cron
- [ ] README setup steps work from a clean clone

**Final report.**
