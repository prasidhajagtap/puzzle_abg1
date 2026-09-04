-- ============================================================================
-- ROLLBACK for 03_sprint_and_powerups.sql
--
-- Removes Sprint mode and power-ups completely and leaves the database
-- exactly as it was. Nothing belonging to the daily game is touched:
-- scores, submit_score, leaderboard_today and leaderboard_week are not
-- referenced here at all.
--
-- WARNING: dropping the tables deletes every Sprint score and every
-- power-up count recorded so far. If you only want to switch the feature
-- off, remove the grants instead and leave the data:
--
--   revoke execute on function public.submit_sprint_score(uuid,int,int,int,int,int) from anon;
--   revoke execute on function public.use_powerup(uuid) from anon;
--   revoke execute on function public.my_powerups(uuid) from anon;
--   revoke select   on public.leaderboard_sprint_today from anon;
-- ============================================================================

drop function if exists public.submit_sprint_score(uuid, int, int, int, int, int);
drop function if exists public.use_powerup(uuid);
drop function if exists public.my_powerups(uuid);
drop view     if exists public.leaderboard_sprint_today;
drop table    if exists public.sprint_scores;
drop table    if exists public.powerups;
