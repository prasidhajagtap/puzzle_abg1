-- ============================================================================
-- Rollback for 10_sprint_week_and_alltime.sql
--
-- Removes ONLY the two views that file created. leaderboard_sprint_today,
-- sprint_scores, and everything else are untouched.
--
-- After running this the game's Sprint "This week" and "All time" tabs go
-- back to having nothing behind them, and the client shows its "this board is
-- not set up yet" message rather than an empty list.
-- ============================================================================

drop view if exists public.leaderboard_sprint_week;
drop view if exists public.leaderboard_sprint_alltime;
