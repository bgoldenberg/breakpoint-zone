> **Superseded.** This was written before the correct repo (`bgoldenberg/Breakpoint-zone-app`) was attached. The accurate, complete version is the patch `breakpoint-zone-app-handoff-2026-11-20.patch` in this folder: in the app repo run `git am /path/to/breakpoint-zone-app-handoff-2026-11-20.patch` (adds a 2026-11-20 entry to `docs/HANDOFF.md` plus `docs/handoff-2026-11-20/`). Key corrections: the stall was the live-match gate in `api/match-highlights/sync.ts`, not a dead job, and the refresh pass re-matches old videos against only yesterday+today fixtures, which will overwrite the relink at the next live tick.

# Handoff: Nitto ATP Finals 2026 highlights (written Nov 20, 2026, ~02:30 UTC)

## Goal
Videos from the Tennis TV YouTube channel (`@tennistv`, channel id `UCbcxFkd6B9xUU54InHv4Tig`) for the
Nitto ATP Finals singles and doubles were not being pulled / published on breakpoint.zone.

## What was done (all in Supabase project "Breakpoint - Fun Facts", table `public.match_highlights`)

1. **Backfilled 3 missing videos** (uploaded after the ingestion job's last run), all `status = 'published'`:

   | video_id | title | match |
   |---|---|---|
   | `IFwl5Y_uTdo` | Dramatic Ending In Zverev vs Fils Match! | 12179706 Zverev v Fils |
   | `Fa0j6w3wMx4` | DIFFERENT VIEW: Zverev's Winning Moment vs Fils | 12179706 Zverev v Fils |
   | `zYNf3gxdSPI` | Shelton Faces Jodar; Zverev vs Fils (Day 5 Highlights, daily) | 12179704 Shelton v Jodar (first-named match, matching Day 3/4 convention) |

   Compared ~60 recent channel uploads against the table; those were the only missing 2026 Finals match
   videos. Doubles (Days 1-5) were all present. Practice sessions / pre-event press conferences / archive
   replays were intentionally not treated as "singles and doubles" match videos.

2. **Re-linked 58 singles rows to the correct match.** The matcher had attached many videos to the wrong
   match (e.g. Fils v Jodar clips on "Shelton v Jodar", Alcaraz v Tiafoe clips on "Alcaraz v Medvedev").
   Fix is `handoff/relink_singles.sql` (idempotent, rules documented in the header).
   Undo with `handoff/rollback_relink.sql`. After the fix every singles match has its own videos.

## What is NOT done / open

1. **Ingestion job is stalled (root cause not found).**
   - Writer is a Node process that upserts `match_highlights?on_conflict=video_id`, roughly hourly
     at :00. Last write: **2026-11-19 21:00 UTC**. Nothing since.
   - The app source is private and was not accessible from the cloud session, and Vercel exposed no
     cron/file tree for the deployment. Runtime logs on the plan only go back ~1h, so no error was visible.
   - To do on the Mac: find the job (Vercel cron in `vercel.json`, a serverless function, or an n8n
     workflow), check its latest runs/errors, fix and re-run it. Projects on Vercel: `breakpoint-zone-app`
     and `-bgoldenberg-breakpoint.zone` (the one serving breakpoint.zone).
   - Until fixed, new uploads (semifinals Nov 21, final Nov 22) will not appear.

2. **The matcher is the real bug, and it can undo the relink.** The hourly upsert's column list includes
   `match_id`, `match_label`, `match_confidence`, `tournament_key`. Any video the job re-processes can be
   overwritten with its (wrong) match. Symptoms to fix in the matcher: it appears to attach by loose
   player-name overlap without respecting the match day, so single-player or multi-match titles land on
   the wrong match. The rules in `relink_singles.sql` (day from title/publish date + the pair named in the
   title) are a reasonable spec. After fixing the matcher, re-run `relink_singles.sql` as a sanity pass.

3. **Doubles links not audited.** Several doubles rows point at the wrong day's match (e.g. "Luz Goes
   Around The Net", published Nov 16, is linked to the Day 5 Arevalo/Pavic v Luz/Matos match, 12179713).
   Needs the day-by-day doubles fixtures (api-tennis) to fix properly. Known IDs so far:
   12179708 Arribage/Olivetti v Luz/Matos, 12179709 Heliovaara/Patten v Arevalo/Pavic,
   12179710 Heliovaara/Patten v Arribage/Olivetti, 12179713 Arevalo/Pavic v Luz/Matos,
   12179715 Harrison/Skupski v Bolelli/Vavassori.

4. **Semifinals / final**: `relink_singles.sql` only knows round-robin fixtures (Nov 15-19). Add the
   semifinal and final match IDs and dates to its `VALUES` list when they exist.

## How to run from the Mac

Run the SQL in the Supabase SQL editor for the "Breakpoint - Fun Facts" project, or with `psql`
using the project's connection string from the Supabase dashboard (do not paste credentials into this repo).

1. Optional dry run: edit the last statement of `relink_singles.sql` as described in its header and run.
2. Run `handoff/relink_singles.sql` (safe to repeat).
3. Verify:
   ```sql
   select match_label, count(*) from match_highlights
   where tournament_key = 2794 and published_at >= '2026-11-15' and match_label is not null
   group by 1 order by 1;
   ```
   Expected after the fix on Nov 20: Alcaraz v Medvedev 15, Alcaraz v Tiafoe 13, Cobolli v Tiafoe 9,
   Fils v Jodar 11, Medvedev v Cobolli 2, Shelton v Fils 12, Shelton v Jodar 12, Zverev v Fils 12,
   Zverev v Jodar 6, Zverev v Shelton 11.
4. To pull anything the job missed, compare the channel's Videos tab (newest first) against
   `select video_id from match_highlights` and insert missing Finals videos using the same columns as the
   existing rows (`video_id, title, channel_name, channel_id, thumbnail_url, duration_seconds, view_count,
   embeddable, published_at, day, category, tournament_key, event_type_type, match_id, match_label,
   match_confidence, status`). Singles `tournament_key` = 2794, doubles = 2795. The frontend reads rows by
   `day` for a window of today +/- 1-2 days with `status = 'published'`.
5. To undo the relink: run `handoff/rollback_relink.sql`.
