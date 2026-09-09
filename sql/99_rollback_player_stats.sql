-- ============================================================================
-- Undo 18_player_stats.sql.
--
-- my_stats is additive — it was a new function, nothing was replaced — so
-- removing it puts the database back exactly as it was. Dropping a function
-- takes its grants with it, so there is nothing else to clean up.
--
-- The game keeps working without it. The client treats a missing my_stats as
-- "no stats to show" and hides the streak banner rather than failing, so this
-- is safe to run even while build 23 is live.
-- ============================================================================

drop function if exists public.my_stats(uuid);
