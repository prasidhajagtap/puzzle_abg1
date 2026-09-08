-- ============================================================================
-- Verify 12_sprint_five_minutes.sql. Reads only.
-- ============================================================================

-- 1. The window the server now enforces. Expect 300, and false.
select
  case when pg_get_functiondef(p.oid) like '%v_window constant int := 300%' then 300
       when pg_get_functiondef(p.oid) like '%v_window constant int := 600%' then 600
       else null end                                            as sprint_window_now,
  pg_get_functiondef(p.oid) like '%v_window constant int := 600%' as old_window_still_there,
  p.prosecdef                                                    as still_security_definer
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='submit_sprint_score';

-- 2. The flag line did NOT move with the clock. Expect true — see the note in 12.
select pg_get_functiondef(p.oid) like '%p_puzzles_cleared > 20%' as flag_still_at_20
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='submit_sprint_score';

-- 3. Which runs were played on which clock. Version 1 is the ten-minute
--    sprint, version 2 the five-minute one. Until version 1 rows age out of
--    the week window, the week and all-time boards mix the two.
select scoring_version,
       count(*)            as runs,
       min(duration_sec)   as shortest,
       max(duration_sec)   as longest,
       max(puzzles_cleared) as best_run
  from public.sprint_scores
 group by scoring_version
 order by scoring_version;

-- 4. Any run longer than the new window is by definition an old one.
select count(*) as runs_longer_than_5_minutes
  from public.sprint_scores where duration_sec > 300;
