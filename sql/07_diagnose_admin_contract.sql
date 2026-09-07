-- ============================================================================
-- The Daily Nine — read-only diagnostic
--
-- Answers, in one paste, the questions the admin console cannot see:
--   5. Are p_build / p_agent persisted anywhere?
--   6. Does login_player read min_build from the same place admin_set_min_build
--      writes it? (If not, the kill switch is not connected end to end.)
--   7. The bodies of login_player and resume_session.
--   8. The column lists of players and sessions.
--   9. The leaderboard view definitions.
--  10. Is username unique — and are there duplicates right now?
--
-- READS ONLY. No CREATE, no ALTER, no INSERT, no UPDATE, no DELETE.
-- Safe to run on production and safe to re-run.
--
-- Run PART A first and send me the whole grid. Then run PART B statements one
-- at a time and send me the text they return.
-- ============================================================================


-- ===========================================================================
-- PART A — one query, one result grid. Send me all of it.
-- ===========================================================================

with

-- ---- Q5: is the build number stored on players? -------------------------
build_cols as (
  select 'Q5  build/agent columns on players' as section,
         column_name as item,
         data_type   as value
    from information_schema.columns
   where table_schema = 'public' and table_name = 'players'
     and (column_name ilike '%build%' or column_name ilike '%agent%'
          or column_name ilike '%last_seen%' or column_name ilike '%device%')
),

-- ---- Q5: is there a per-sign-in log table? ------------------------------
login_tables as (
  select 'Q5  candidate login-log tables' as section,
         table_name as item,
         'table'    as value
    from information_schema.tables
   where table_schema = 'public'
     and (table_name ilike '%login%' or table_name ilike '%event%'
          or table_name ilike '%audit%' or table_name ilike '%visit%')
),

-- ---- Q6: where could a min_build setting live? --------------------------
setting_tables as (
  select 'Q6  candidate settings tables' as section,
         table_name as item,
         'table'    as value
    from information_schema.tables
   where table_schema = 'public'
     and (table_name ilike '%setting%' or table_name ilike '%config%'
          or table_name ilike '%admin%'  or table_name ilike '%flag%')
),

-- ---- Q6: which functions even mention min_build? ------------------------
minbuild_fns as (
  select 'Q6  functions mentioning min_build' as section,
         p.proname as item,
         case when pg_get_functiondef(p.oid) ilike '%min_build%'
              then 'mentions min_build' else '-' end as value
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and pg_get_functiondef(p.oid) ilike '%min_build%'
),

-- ---- Q8: the columns of players and sessions ----------------------------
core_cols as (
  select 'Q8  ' || table_name || ' columns' as section,
         ordinal_position || '. ' || column_name as item,
         data_type || case when is_nullable = 'NO' then ' not null' else '' end as value
    from information_schema.columns
   where table_schema = 'public' and table_name in ('players','sessions')
),

-- ---- Q10: is username unique? -------------------------------------------
uname_constraint as (
  select 'Q10 unique constraints on players' as section,
         i.indexname as item,
         i.indexdef  as value
    from pg_indexes i
   where i.schemaname = 'public' and i.tablename = 'players'
),
uname_dupes as (
  select 'Q10 duplicate usernames right now' as section,
         'case-insensitive duplicate names' as item,
         count(*)::text as value
    from (select lower(username) u
            from public.players
           group by 1 having count(*) > 1) d
),
uname_dupes_exact as (
  select 'Q10 duplicate usernames right now' as section,
         'exact duplicate names' as item,
         count(*)::text as value
    from (select username
            from public.players
           group by 1 having count(*) > 1) d
),

-- ---- context: what the console will be reading --------------------------
row_counts as (
  select 'CTX row counts' as section, 'players'        as item, count(*)::text as value from public.players
  union all
  select 'CTX row counts', 'sessions live',  count(*)::text from public.sessions where expires_at > now()
  union all
  select 'CTX row counts', 'scores',         count(*)::text from public.scores
  union all
  select 'CTX row counts', 'sprint_scores',  count(*)::text from public.sprint_scores
  union all
  select 'CTX row counts', 'powerups',       count(*)::text from public.powerups
),

-- ---- context: every function the two apps rely on -----------------------
fn_list as (
  select 'CTX functions present' as section,
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as item,
         case when p.prosecdef then 'SECURITY DEFINER' else 'invoker' end as value
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'admin/_%' escape '/'
          or p.proname in ('login_player','resume_session','register_player',
                           'end_session','reset_pin','ack_secret','my_history',
                           'my_powerups','use_powerup','submit_score',
                           'submit_sprint_score'))
),

-- ---- context: RLS state, so we can see nothing has drifted --------------
rls as (
  select 'CTX row level security' as section,
         c.relname as item,
         case when c.relrowsecurity then 'RLS ON' else 'RLS OFF' end as value
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('players','sessions','scores','sprint_scores','powerups')
)

select * from build_cols
union all select * from login_tables
union all select * from setting_tables
union all select * from minbuild_fns
union all select * from core_cols
union all select * from uname_constraint
union all select * from uname_dupes
union all select * from uname_dupes_exact
union all select * from row_counts
union all select * from fn_list
union all select * from rls
order by section, item;


-- ===========================================================================
-- PART B — run these one at a time and paste back the text.
-- These are the function bodies. I will not write the min_build migration
-- from a guess; I need to see what is actually there.
-- ===========================================================================

-- B1. The two functions that hand min_build to the game.
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'login_player';

-- B2.
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'resume_session';

-- B3. The function the console writes min_build with. Comparing B1 and B3
--     tells us whether the kill switch is connected end to end.
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'admin_set_min_build';

-- B4. What the console reads min_build and the build spread from.
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'admin_overview';

-- B5. Q9 — the leaderboard views the game reads directly.
select table_name, view_definition
  from information_schema.views
 where table_schema = 'public'
   and table_name like 'leaderboard%'
 order by table_name;

-- B6. Only if PART A showed a login-log table. Replace the name.
-- select column_name, data_type from information_schema.columns
--  where table_schema = 'public' and table_name = '<the table PART A found>'
--  order by ordinal_position;
