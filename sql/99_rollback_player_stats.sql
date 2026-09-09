-- ============================================================================
-- Undo 18_player_stats.sql.
--
-- All three functions were new — nothing was replaced — so removing them puts
-- the database back exactly as it was. Dropping a function takes its grants
-- with it, so there is nothing else to clean up.
--
-- Order matters: my_stats calls dn_streak, which calls dn_workday_no, so they
-- come off in that order. Without "if exists" a partial rollback would stop
-- half way.
--
-- The game keeps working without them. The client treats a missing my_stats
-- as "no stats to show" and hides the streak strip rather than failing, so
-- this is safe to run even while build 23 is live: the mode screen simply
-- looks like build 22 again.
--
-- Nothing here touches a score.
-- ============================================================================

drop function if exists public.my_stats(uuid);
drop function if exists public.dn_streak(text, date);
drop function if exists public.dn_workday_no(date);
