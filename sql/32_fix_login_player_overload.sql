-- ============================================================================
-- The Daily Nine — the THIRD duplicated function, and the worst of them
--
-- HOW IT WAS FOUND. 31_verify_submit_score_overload.sql ends with V3, a sweep
-- that asks the whole schema "does any function exist in more than one
-- version?" It was written because 30 was the second time this fault had been
-- found by accident, and guessing where else it lived was not good enough.
-- It returned one row:
--
--     fn                   versions   arg_counts
--     public.login_player  2          2 and 4
--
-- CONFIRMED AGAINST THE LIVE API, not inferred:
--
--   login_player(p_username, p_pin, p_build, p_agent)  -> 200, works
--   login_player(p_username, p_pin)                    -> 300 PGRST203
--
-- WHY THIS ONE IS WORSE THAN 26 AND 30. resume_session degraded a session and
-- submit_score lost a score. This is the SIGN-IN. A client that sends two
-- arguments cannot get past the login screen at all — not a bad password, not
-- a helpful error, just a 300 the client was never written to expect. The
-- player is locked out of the game and nothing on their screen explains why.
--
-- Who sends two arguments: any copy of the game from before p_build and
-- p_agent were added, sitting in a browser cache or an installed PWA that has
-- not updated. Those are exactly the players who cannot fix it themselves,
-- because fixing it would mean loading the new build, and they cannot get in.
--
-- THE FIX IS THE SAME ONE DROP, AND NEEDS NO FUNCTION BODY. PostgREST offered
-- BOTH functions as candidates for a two-argument call. It can only do that if
-- the four-argument version's p_build and p_agent already have DEFAULTs —
-- otherwise two arguments could not satisfy it and it would not be a
-- candidate. So the four-argument version already answers a two-argument call
-- on its own, with p_build and p_agent coming through as their defaults.
-- Dropping the old version does not remove a path; it uncovers the one that
-- should have been reached all along. PART A proves this before anything goes.
--
-- NOTHING IS TOUCHED BUT THE FUNCTION. No player row, no session, no score.
--
-- >>> RUN PART A FIRST AND READ IT. <<< If A1 does not show TWO rows, or if
-- the four-argument row does not show 2 defaults, STOP — the database is not
-- in the state this file was written for, and dropping would break sign-in
-- rather than fix it.
--
-- Safe to re-run. Rollback: 99_rollback_login_player_overload.sql
-- Verify: 33_verify_login_player_overload.sql
-- ============================================================================


-- ===========================================================================
-- PART A — READ ONLY. The proof, before the drop.
-- ===========================================================================

-- A1. Both versions and, crucially, how many of each one's arguments are
--     DEFAULTED. The 4-argument row MUST show defaulted = 2. That is the
--     whole safety argument: it is what lets it answer a 2-argument call.
select p.oid::regprocedure  as signature,
       p.pronargs           as arguments,
       p.pronargdefaults    as defaulted,
       case
         when p.pronargs = 4 and p.pronargdefaults = 2
           then 'KEEP — answers both call shapes'
         when p.pronargs = 2
           then 'DROP — unreachable through PostgREST, and it is what causes the 300'
         else 'UNEXPECTED — do not run PART B'
       end as verdict
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'login_player'
 order by p.pronargs;

-- A2. Who can execute each version today, so PART C can be checked afterwards.
select p.oid::regprocedure as signature,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'login_player'
 order by p.pronargs;


-- ===========================================================================
-- PART B — THE CHANGE. One statement.
-- ===========================================================================

-- Spelled out in full so it can only ever match the old two-argument version.
drop function if exists public.login_player(text, text);


-- ===========================================================================
-- PART C — the grants, restated. A drop cannot carry a grant away with it,
-- but if anyone has recreated the remaining function by hand these put the
-- browser back in business. anon MUST keep EXECUTE or nobody can sign in.
-- ===========================================================================
grant execute on function public.login_player(text, text, integer, text)
  to anon, authenticated;
