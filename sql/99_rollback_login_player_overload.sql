-- ============================================================================
-- Rollback for 32.
--
-- There is nothing to put back. 32 drops a function that could not be reached
-- unambiguously through PostgREST — every call that matched it returned 300
-- rather than running it. The function that remains answers every call the
-- dropped one did, because p_build and p_agent default.
--
-- If the two-argument version is genuinely wanted again it must be recreated
-- from its original body — take it from a backup, not from here. Writing it
-- out from memory is how the two drifted apart in the first place, and on the
-- SIGN-IN path a guessed body is a security problem, not just a bug.
--
-- The only thing worth restating is the grant, in case it was disturbed:
-- ============================================================================
grant execute on function public.login_player(text, text, integer, text)
  to anon, authenticated;
