-- Read-only. Run after 05_lock_down_sprint_tables.sql. ----------------------

-- 1. anon must NOT be able to touch either table. Expect false for all six.
SELECT 'sprint_scores' AS tbl,
       has_table_privilege('anon','public.sprint_scores','SELECT') AS sel,
       has_table_privilege('anon','public.sprint_scores','INSERT') AS ins,
       has_table_privilege('anon','public.sprint_scores','DELETE') AS del
UNION ALL
SELECT 'powerups',
       has_table_privilege('anon','public.powerups','SELECT'),
       has_table_privilege('anon','public.powerups','INSERT'),
       has_table_privilege('anon','public.powerups','DELETE');

-- 2. RLS is on for both. Expect true, true.
SELECT relname, relrowsecurity
FROM pg_class WHERE relname IN ('sprint_scores','powerups');

-- 3. The leaderboard the browser reads must STILL be readable. Expect true.
SELECT has_table_privilege('anon','public.leaderboard_sprint_today','SELECT') AS board_readable;

-- 4. And it must still actually return rows rather than erroring.
--    (Empty is fine until someone plays; an ERROR here is not.)
SELECT * FROM public.leaderboard_sprint_today ORDER BY rank LIMIT 5;

-- 5. The daily game must be untouched. Expect false, and true.
SELECT has_table_privilege('anon','public.scores','SELECT') AS scores_still_locked_false,
       has_table_privilege('anon','public.leaderboard_today','SELECT') AS daily_board_readable;
