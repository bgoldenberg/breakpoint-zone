-- Re-link Nitto ATP Finals 2026 SINGLES highlights to the match actually played that day.
-- Target DB: Supabase project "Breakpoint - Fun Facts", table public.match_highlights.
-- Idempotent: rows already on the right match are untouched (WHERE mh.match_id <> p.mid).
--
-- To DRY-RUN: replace the final UPDATE statement with
--   select video_id, left(title,70) t, category, curlbl, lbl as newlbl, kind from pick where cur <> mid order by lbl, video_id;
--
-- Rules
--  * Round-robin schedule (singles), one match per player per day:
--      Nov 15: Zverev-Jodar 12179707, Shelton-Fils 12179703
--      Nov 16: Alcaraz-Tiafoe 12179698, Medvedev-Cobolli 12179701
--      Nov 17: Fils-Jodar 12179700, Zverev-Shelton 12179705
--      Nov 18: Alcaraz-Medvedev 12179696, Cobolli-Tiafoe 12179699
--      Nov 19: Shelton-Jodar 12179704, Zverev-Fils 12179706
--  * Day = "Day N" in the title if present, else the UTC publish date.
--  * Title naming both players of a match that day -> that match ('confirmed' if "vs", non-daily).
--  * Daily recaps naming several matches -> the first-named pair ('probable').
--  * Title naming exactly one player -> that player's match that day ('probable').
--  * Skips archive / practice / preview / ceremony / season-review titles.
--  * Doubles are NOT handled (doubles fixture IDs per day are not known here).
-- Extend the VALUES list and the date range for semifinals / final (Nov 21-22+) once fixtures exist.

with m(d,p1,p2,mid,lbl) as (values
('2026-11-15'::date,'zverev','jodar','12179707','Zverev v Jodar'),('2026-11-15','shelton','fils','12179703','Shelton v Fils'),
('2026-11-16','alcaraz','tiafoe','12179698','Alcaraz v Tiafoe'),('2026-11-16','medvedev','cobolli','12179701','Medvedev v Cobolli'),
('2026-11-17','fils','jodar','12179700','Fils v Jodar'),('2026-11-17','zverev','shelton','12179705','Zverev v Shelton'),
('2026-11-18','alcaraz','medvedev','12179696','Alcaraz v Medvedev'),('2026-11-18','cobolli','tiafoe','12179699','Cobolli v Tiafoe'),
('2026-11-19','shelton','jodar','12179704','Shelton v Jodar'),('2026-11-19','zverev','fils','12179706','Zverev v Fils')),
v as (select video_id,title,category,match_id cur,match_label curlbl,
  coalesce(case when title ~* '\mday 1\M' then date '2026-11-15' when title ~* '\mday 2\M' then date '2026-11-16' when title ~* '\mday 3\M' then date '2026-11-17' when title ~* '\mday 4\M' then date '2026-11-18' when title ~* '\mday 5\M' then date '2026-11-19' end,(published_at at time zone 'utc')::date) d,
  (select count(*) from unnest(array['zverev','jodar','shelton','fils','alcaraz','tiafoe','medvedev','cobolli']) s where lower(title) like '%'||s||'%') n_hits
 from match_highlights where tournament_key=2794 and published_at>='2026-11-15' and title !~* '(2023|2024|2025|hamburg|tokyo|practice|preview|ceremony|year-end|season|breakthrough|written in the stars)'),
c as (select v.*, m.mid, m.lbl, position(m.p1 in lower(v.title)) a, position(m.p2 in lower(v.title)) b from v join m on m.d=v.d),
cand as (
 select video_id,title,category,cur,curlbl,mid,lbl,'pair' kind,least(a,b) pos, count(*) over (partition by video_id) np from c where a>0 and b>0
 union all select video_id,title,category,cur,curlbl,mid,lbl,'single',0,1 from c where n_hits=1 and (a>0 or b>0)),
pick as (select distinct on (video_id) * from cand where kind='single' or category='daily' or np=1 order by video_id, case kind when 'pair' then 0 else 1 end, pos)
update match_highlights mh set match_id=p.mid, match_label=p.lbl, tournament_key=2794, event_type_type='Atp Singles',
  match_confidence = case when p.kind='pair' and p.category<>'daily' and p.title ~* ' (vs|v)\.? ' then 'confirmed' else 'probable' end,
  updated_at = now()
from pick p where mh.video_id=p.video_id and mh.match_id<>p.mid;
