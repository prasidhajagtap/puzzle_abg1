-- Read-only. Run after 03_sprint_and_powerups.sql. ---------------------------

-- 1. The new objects exist. Expect 2 tables, 1 view, 3 functions.
SELECT 'table' AS kind, tablename AS name FROM pg_tables
 WHERE schemaname='public' AND tablename IN ('sprint_scores','powerups')
UNION ALL
SELECT 'view', viewname FROM pg_views
 WHERE schemaname='public' AND viewname='leaderboard_sprint_today'
UNION ALL
SELECT 'function', p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('my_powerups','use_powerup','submit_sprint_score')
ORDER BY 1,2;

-- 2. The browser role must be able to call the functions and read the view,
--    and must NOT be able to touch the tables directly.
--    Expect: has_table_privilege = false for both tables, true for the view.
SELECT 'sprint_scores' AS obj, has_table_privilege('anon','public.sprint_scores','SELECT') AS anon_can_select
UNION ALL SELECT 'powerups', has_table_privilege('anon','public.powerups','SELECT')
UNION ALL SELECT 'leaderboard_sprint_today', has_table_privilege('anon','public.leaderboard_sprint_today','SELECT');

-- 3. Nothing existing was disturbed. Expect the daily function still overwrites.
SELECT position('do update' in pg_get_functiondef(p.oid)) > 0 AS daily_still_overwrites
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='submit_score';

-- 4. Today's sprint board (empty until someone plays).
SELECT * FROM public.leaderboard_sprint_today ORDER BY rank;
