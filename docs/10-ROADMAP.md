# 10. Roadmap and Future Recommendations

Out of scope for the MVP. Do not build these unless asked.

## Next (v1), in recommended order

1. **Email forwarding.** A per-user address that parses forwarded provider emails into a review queue. Highest impact for people who forget, because capture needs no app visit. Needs an inbound-email provider webhook, signature verification and a pending-review list.
2. **Bulk import.** Many screenshots at once, reviewed in one confirmation table. Extends the one-perk extraction schema to an array.
3. **Weekly digest** on Telegram: expiring this week, unclaimed offers, one suggested action.
4. **Student verification tracking** as a first-class perk: renewal date, what it unlocks, and a warning when it lapses.
5. **Calendar feed (.ics)** with a private token URL so expiries show up in the owner's calendar.
6. **Email channel** as a second notification route using the existing `channel` column and unique key.

## Later

- **Burn-rate forecasting:** warn when a credit will go unused before expiry, not only when it will run out. Needs a usage figure per perk.
- **Use-it-or-lose-it planner:** suggest what to build with expiring credits based on their restrictions and the owner's project notes.
- **Browser extension** for one-click screenshot capture on billing pages.
- **Community directory:** a moderated shared list of known programs and deadlines, with a one-click "add to my tracker" that creates an `eligible` perk.
- **Teams:** workspaces, perk owners, handoff notes, approvals. This requires a real multi-tenant model (membership table, policies by workspace), so plan it as a schema change, not a patch.
- **Progressive web app** with push notifications.
- **Model flexibility:** the AI call lives behind one module, so swapping models or using a self-hosted Gemma for privacy is a small change.
- **Retrieval for the ask box** only if a user accumulates hundreds of perks. At small scale, sending the data directly is simpler and more reliable.

## Technical debt to watch

- Move reminders to a queue if send volume grows.
- Add error tracking and basic analytics once there are real users.
- Revisit the Gemma 4 JSON-mode support and switch to structured output if it is reliable, then simplify the parser.
- Add end-to-end tests (Playwright) for the capture and link flows.

## Product principles to keep

- Deterministic code for dates and reminders. AI only for messy input.
- The owner always confirms before anything is saved.
- Never sell or advertise against perk data.
