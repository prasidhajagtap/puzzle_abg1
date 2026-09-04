-- ============================================================================
-- URGENT — run this before Sprint mode goes live.
--
-- WHY: 03_sprint_and_powerups.sql assumed new tables carry no privileges for
-- the browser role. That assumption was WRONG for this project. Supabase's
-- default privileges granted anon full access to both new tables the moment
-- they were created. Verified against the live API:
--
--   POST /rest/v1/sprint_scores  -> 400 (not-null violation, NOT 401)
--                                   i.e. the INSERT was allowed to run
--   DELETE /rest/v1/powerups     -> 204  i.e. the DELETE succeeded
--   GET  /rest/v1/scores         -> 401  the older table is correctly locked
--
-- The risk: anyone holding the public anon key could write sprint scores
-- straight into the table, bypassing submit_sprint_score and therefore its
-- session check, its clamps and its cheat flag — and could delete rows from
-- powerups to hand themselves unlimited power-ups.
--
-- This script closes both, and adds RLS as a second line of defence so a
-- future default-privilege grant cannot silently reopen them.
--
-- Nothing legitimate breaks:
--   * the three RPCs are SECURITY DEFINER and run as their owner, which is
--     not subject to RLS on tables it owns, so they keep full access
--   * leaderboard_sprint_today is a normal view, so it runs with the view
--     owner's rights rather than the caller's, and still reads the table
--   * the browser only ever calls the RPCs and reads that view
-- ============================================================================

-- 1. Take back what the default privileges handed out.
revoke all on public.sprint_scores from anon, authenticated;
revoke all on public.powerups      from anon, authenticated;

-- The identity sequence behind sprint_scores.id too, so no one can poke it.
revoke all on all sequences in schema public from anon;

-- 2. Belt as well as braces. RLS with NO policies denies every row to any
--    role that is subject to it. The table owner is not subject to it, which
--    is exactly why the SECURITY DEFINER functions keep working.
alter table public.sprint_scores enable row level security;
alter table public.powerups      enable row level security;

-- 3. The browser still needs these two things, and only these two.
grant select  on public.leaderboard_sprint_today to anon;
grant execute on function public.my_powerups(uuid)        to anon;
grant execute on function public.use_powerup(uuid)        to anon;
grant execute on function public.submit_sprint_score(uuid, int, int, int, int, int) to anon;

-- 4. Stop the same thing happening to the NEXT table someone creates here.
--    Supabase's default privileges are what caused this; this narrows them.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
