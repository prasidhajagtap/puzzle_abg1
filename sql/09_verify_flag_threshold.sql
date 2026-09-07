-- ============================================================================
-- Verify 08_lower_flag_threshold.sql
--
-- PART A proves the change landed and shows what it means for rows already in
-- the table. It reads only.
--
-- PART B is optional and it WRITES. Read it before running it.
-- ============================================================================


-- ===========================================================================
-- PART A — read only. Run this and send me the two grids.
-- ===========================================================================

-- A1. Did the change land? Expect flag_line_now = 10 and old_line_gone = true.
select
  case when pg_get_functiondef(p.oid) like '%p_time_sec < 10%' then 10
       when pg_get_functiondef(p.oid) like '%p_time_sec < 20%' then 20
       else null end                                            as flag_line_now,
  pg_get_functiondef(p.oid) not like '%p_time_sec < 20%'        as old_line_gone,
  p.prosecdef                                                   as still_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'submit_score';


-- A2. What the change means for rows already stored.
--     Nothing here is altered by A2 itself.
select 'flagged, and still would be (under 10s)'      as bucket,
       count(*)                                        as rows
  from public.scores where flagged and solved and time_sec < 10
union all
select 'flagged, but would NOT be now (10-19s)',
       count(*)
  from public.scores where flagged and solved and time_sec between 10 and 19
union all
select 'flagged for some other reason',
       count(*)
  from public.scores where flagged and not (solved and time_sec < 20)
union all
select 'not flagged',
       count(*)
  from public.scores where not flagged
order by bucket;


-- A3. The rows that the old line caught and the new one would not.
--     These are the players who were marked for being fast.
select p.username, s.play_date, s.time_sec, s.total_points, s.theme
  from public.scores s
  join public.players p using (poornata_id)
 where s.flagged and s.solved and s.time_sec between 10 and 19
 order by s.time_sec, s.play_date desc
 limit 100;


-- ===========================================================================
-- PART B — OPTIONAL, AND IT WRITES.
--
-- The new line only applies to scores submitted from now on. Rows already
-- flagged keep their flag, so the admin console will go on showing players
-- who were caught by a rule that no longer exists.
--
-- This clears the flag on exactly those rows: solved, 10 to 19 seconds, and
-- nothing else. It cannot touch a sub-10-second run, and it cannot set a flag
-- on anything.
--
-- Run A3 first and look at the list. If you are happy that none of those runs
-- deserves a second look, run B1. If you would rather keep the history as it
-- was recorded, skip PART B entirely — it changes nothing about how new
-- scores are judged.
-- ===========================================================================

-- B1. Uncomment to run.
-- update public.scores
--    set flagged = false
--  where flagged and solved and time_sec between 10 and 19;

-- B2. After B1, this should return 0.
-- select count(*) as should_be_zero
--   from public.scores where flagged and solved and time_sec between 10 and 19;
