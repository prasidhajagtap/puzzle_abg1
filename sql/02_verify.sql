-- ============================================================================
-- Run AFTER the migration. Read-only except the two marked test blocks.
-- ============================================================================

-- 1. Confirm the new behaviour is in place (expect: do update ... = t)
SELECT position('do update' in pg_get_functiondef(p.oid)) > 0 AS overwrites_now,
       position('ALREADY_PLAYED_TODAY' in pg_get_functiondef(p.oid)) > 0 AS old_branch_left
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='submit_score';

-- 2. The unique constraint must still exist — ON CONFLICT depends on it.
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint WHERE conname = 'scores_one_per_day';

-- 3. Nobody should have more than one row per day. Expect zero rows.
SELECT poornata_id, play_date, count(*)
FROM public.scores GROUP BY 1,2 HAVING count(*) > 1;

-- 4. Today's board, to eyeball before and after a test replace.
SELECT poornata_id, play_date, total_points, time_sec, words_found,
       attempts, flagged
FROM public.scores WHERE play_date = current_date
ORDER BY total_points DESC;
