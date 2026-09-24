-- ============================================================================
-- The Daily Nine — the duplicate submit_score, found by probing the live API
--
-- WHAT WAS FOUND. Calling submit_score WITHOUT p_time_ms returns
--
--   300  PGRST203  "Could not choose the best candidate function between:
--                   public.submit_score(... p_attempts),
--                   public.submit_score(... p_attempts, p_time_ms)"
--
-- 14_score_tiebreak.sql added p_time_ms with CREATE OR REPLACE. Postgres
-- treats a new parameter list as a NEW function rather than a replacement, so
-- the eight-argument version from before 14 is still sitting there. This is
-- the same fault 26 fixed on resume_session, in the same way, for the same
-- reason — and it was not looked for anywhere else at the time. It should
-- have been.
--
-- WHO IS HURT. Not today's player: the current client always sends p_time_ms,
-- which resolves cleanly to the nine-argument version. It is a client that
-- sends eight arguments:
--
--   * any copy of the game from before 14 still sitting in a browser cache or
--     an installed PWA that has not updated. GitHub Pages caches for ten
--     minutes and an unopened PWA can be far staler than that.
--   * the current client's own fallback path. It exists for the case where
--     this database has no p_time_ms, catches 404 and retries with eight
--     arguments. Today that retry would get 300 rather than 404, and
--     rpc() throws, so the score is lost with an error on screen.
--
-- Either way the player finishes a game and their score does not save.
--
-- THE FIX IS ONE DROP, AND NEEDS NO FUNCTION BODY. 14 declared
--
--     p_attempts integer DEFAULT 1,
--     p_time_ms  integer DEFAULT NULL
--
-- so the nine-argument version already answers an eight-argument call on its
-- own — p_time_ms simply comes through as null, which is exactly what the old
-- rows hold and exactly what 16's ordering already knows how to read. Dropping
-- the old version therefore does not remove a code path, it uncovers the one
-- that should have been reached all along.
--
-- NO SCORES ARE TOUCHED. This drops a function. It does not read, write or
-- recompute one row of scores.
--
-- >>> RUN PART A FIRST AND READ IT. <<< If A1 does not show TWO rows, stop:
-- the database is not in the state this file was written for.
--
-- Safe to re-run. Rollback: 99_rollback_submit_score_overload.sql
-- Verify: 31_verify_submit_score_overload.sql
-- ============================================================================


-- ===========================================================================
-- PART A — READ ONLY. Proof, before anything is dropped.
-- ===========================================================================

-- A1. Both versions, and which one has the defaults. Expect exactly two rows:
--     one with 8 arguments and 1 default, one with 9 arguments and 2 defaults.
--     The 9-argument row having pronargdefaults = 2 is the whole argument for
--     this being safe — it is what lets it answer an 8-argument call.
select p.oid::regprocedure                as signature,
       p.pronargs                         as arguments,
       p.pronargdefaults                  as defaulted,
       case when p.pronargs = 9 then 'KEPT — answers both call shapes'
            else                    'DROPPED by PART B' end as verdict
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'submit_score'
 order by p.pronargs;

-- A2. The same question asked of the live API rather than the catalogue:
--     how many overloads PostgREST can see. Anything but 2 means A1 and the
--     API disagree and this file should not be run.
select count(*) as overloads_visible_to_postgrest
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'submit_score';


-- ===========================================================================
-- PART B — THE CHANGE. One statement.
-- ===========================================================================

-- The argument list is spelled out in full so this can only ever match the
-- old version. If 14 was never applied this drops nothing and errors nothing,
-- because the signature simply will not be found.
drop function if exists public.submit_score(
  uuid, text, integer, integer, integer, integer, boolean, integer);


-- ===========================================================================
-- PART C — the grants, restated. A drop cannot take a grant with it, but if
-- someone has recreated the remaining function by hand these put the browser
-- back in business. anon must keep EXECUTE or nobody can submit a score.
-- ===========================================================================
grant execute on function public.submit_score(
  uuid, text, integer, integer, integer, integer, boolean, integer, integer)
  to anon, authenticated;
