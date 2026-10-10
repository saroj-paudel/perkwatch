# 07. Security and Privacy

## Assets

The owner's perk list, notification settings (including Telegram chat id), and the API keys (Gemini, Supabase service role, Telegram bot, cron and webhook secrets).

## Threats and controls

| Threat | Control |
| --- | --- |
| Another person signs in | Signups disabled in Supabase. `shouldCreateUser: false`. Owner email check in the layout. Data protected by RLS regardless |
| Data read through the anon key | RLS on every table. Policies in the migration. Test with a second throwaway user |
| Secret leaks to the browser | `server-only` imports. Only `NEXT_PUBLIC_*` variables are public. Never return env values from any route |
| Forged Telegram webhook calls | Secret header `X-Telegram-Bot-Api-Secret-Token` compared in constant time. Reject with 401 |
| Forged cron calls | Bearer `CRON_SECRET` compared in constant time. Reject with 401 |
| Linking someone else's Telegram | One-time code, 10 minute expiry, single use, tied to the user who created it. Chat id unique |
| Prompt injection in screenshots or emails | Model output only fills a form the owner confirms. The model has no tools and cannot write. Model text is rendered as plain text. The prompt tells the model to ignore embedded instructions |
| Cost abuse of the AI endpoint | Auth required, size limits, `AI_DAILY_LIMIT` through an atomic RPC |
| Malicious upload | Allow-list of MIME types (checked by content sniffing the first bytes, not only the header), size limit, never written to disk, never executed |
| XSS | React escapes by default. Never use `dangerouslySetInnerHTML`. Telegram messages use `escapeHtml` on every user-supplied string |
| CSRF on server actions | Rely on Next.js Server Action protections and same-site cookies. Do not add GET routes that mutate data (cron is the exception and is secret-protected) |
| Overlong or malformed input | zod on every boundary plus database check constraints |
| Information leaks in errors and logs | Standard error shape with codes. No stack traces to clients. No tokens, emails, screenshot bytes or pasted text in logs |

## Privacy rules

- Screenshots and pasted text are sent to the Gemini API for extraction and are **not stored by Perkwatch**. Say this on the Add page in one plain sentence, including that the content is processed by Google's API.
- Only the fields the owner confirms are saved.
- Remind the owner to hide account ids and emails in screenshots when possible.
- Logs record event names, user id, sizes and outcome codes only.
- Check Google's current terms for data use on the Gemini API tier in use, and note the result in the README before sharing the app with others.

## Headers and cookies

- Set security headers in `next.config` (`X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options: DENY`).
- Supabase session cookies are managed by `@supabase/ssr`. Do not store tokens in `localStorage`.

## Secrets handling

- `.env.local` is git-ignored. `.env.example` has placeholders only.
- Rotate the Telegram token, service-role key, webhook secret and cron secret if any of them is ever pasted into a public place.

## Pre-release security checklist

- [ ] RLS verified with a second user: cannot read or change the owner's rows
- [ ] Service-role key not present in any client bundle (search the build output)
- [ ] Webhook and cron return 401 without the secret
- [ ] Upload of a non-image file is rejected with 415
- [ ] Oversized upload is rejected with 413
- [ ] Signup is disabled in Supabase
- [ ] No secrets or personal data in the repository history
