-- ============================================================================
-- Word Vibe - fair boards for a public launch
--
-- Three problems, found by the launch check before opening the game to
-- everyone:
--
-- 1. ANY USERNAME. A rude or fake-official name went straight onto a public
--    leaderboard, and the admin had no way to take it off.
--    FIX: a name check on the players table itself (a trigger), so it holds
--    whichever function writes the row, and a "hidden" flag the admin console
--    can set (see streak_Admin sql/A09). A hidden player can still sign in and
--    play; they just do not appear on any board.
--
-- 2. FLAGGED SCORES STILL RANKED. submit_score and submit_sprint_score flag
--    impossible results (a daily solve under 10 seconds, a sprint over 20
--    puzzles) "so a prize list can be audited", but the boards showed them
--    anyway, at the top.
--    FIX: every board leaves out flagged rows. Nothing is deleted; the rows
--    stay in scores and sprint_scores, and the admin's Flagged tab still
--    lists them.
--
-- 3. PAST 100 PLAYERS. Five boards stopped at 100 rows INSIDE the view. That
--    also cut off every server function that looks a player up on them:
--    submit_score's "You are #N" and "who else played today" both stopped at
--    100. The sprint-today board had no limit at all.
--    FIX: the views have no row limit now, so a rank of 150 is a real rank.
--    The game asks for the top 100 itself (&limit=100), which keeps the
--    download small. PostgREST's own row cap still applies to anyone else.
--
-- Also: an index on play_date for scores and sprint_scores. Every "today" and
-- "this week" board filters on it, and without one each read scans every
-- score ever played.
--
-- WHAT IT DOES NOT CHANGE. No score, no player row, no function the game
-- calls, no existing username. The name check applies to NEW names only;
-- check 9 at the bottom counts existing names it would have stopped, so they
-- can be hidden by hand.
--
-- SAFETY. It all runs in one transaction. Step 0 compares the six boards'
-- columns with what this file was written against; if any differ it stops
-- and nothing at all is changed.
--
-- THE LAST QUERY IS A CHECKLIST. Every row should read ok = true.
-- Rows marked (info) have no right answer.
--
-- Safe to re-run. Rollback: 99_rollback_fair_boards.sql
-- ============================================================================

begin;

-- ------------------------------------------------------------ 0. the guard ---
do $guard$
declare
  r record;
  v_have text;
begin
  for r in select * from (values
    ('leaderboard_today',          'rank,username,total_points,word_points,time_points,streak_bonus,time_sec,words_found,words_total,solved,theme,time_ms'),
    ('leaderboard_week',           'rank,username,total_points,games_played,games_solved,best_time'),
    ('leaderboard_alltime',        'rank,username,total_points,games_played,games_solved,best_time,last_played'),
    ('leaderboard_sprint_today',   'rank,username,puzzles_cleared,words_found,duration_sec,powerups_used,flagged'),
    ('leaderboard_sprint_week',    'rank,username,puzzles_cleared,words_found,runs,best_run,flagged'),
    ('leaderboard_sprint_alltime', 'rank,username,puzzles_cleared,words_found,runs,best_run,last_played,flagged')
  ) as t(view_name, cols)
  loop
    select string_agg(a.attname, ',' order by a.attnum) into v_have
      from pg_attribute a
     where a.attrelid = to_regclass('public.' || r.view_name)
       and a.attnum > 0 and not a.attisdropped;
    if v_have is distinct from r.cols then
      raise exception 'STOPPED, nothing changed: % has columns [%], this file expects [%]',
        r.view_name, coalesce(v_have, 'view missing'), r.cols;
    end if;
  end loop;
end
$guard$;


-- ------------------------------------------------------ 1. hidden players ---
alter table public.players add column if not exists hidden    boolean not null default false;
alter table public.players add column if not exists hidden_at timestamptz;
alter table public.players add column if not exists hidden_by text;


-- ---------------------------------------------------------- 2. name check ---
-- The words live in a table so more can be added from the SQL editor without
-- touching a function:
--     insert into public.blocked_name_words values ('someword', 'word', 'rude');
--
-- how = 'part' : blocked anywhere inside the name, even run together
--                ("xfuckx"). Only words that are almost never innocent.
-- how = 'word' : blocked only as a whole word ("big dick", "d i c k"), because
--                as a part it hits real names: dick/Dickens, sex/Essex,
--                rape/grape, nazi/Nazia, randi/Brandi, lund/Lund, shit/Ashita,
--                rapist/therapist, admin/badminton, porn/Poornima (squeezed),
--                boob/Boobalan, twat/Atwater, gandu/Gandule.
-- Before matching, a name is lower-cased, digits that stand in for letters
-- are read as letters (0=o 1=i or l 3=e 4=a 5=s 7=t 8=b), and repeated
-- letters are also tried squeezed to one ("fuuuck").
create table if not exists public.blocked_name_words (
  word   text primary key check (word = lower(word) and word ~ '^[a-z]+$'),
  how    text not null check (how in ('part', 'word')),
  reason text not null check (reason in ('rude', 'reserved'))
);
alter table public.blocked_name_words enable row level security;
revoke all on public.blocked_name_words from public, anon, authenticated;

insert into public.blocked_name_words (word, how, reason) values
  -- English, blocked anywhere in the name
  ('fuck','part','rude'),('phuck','part','rude'),('cunt','part','rude'),
  ('bitch','part','rude'),('bastard','part','rude'),('asshole','part','rude'),
  ('arsehole','part','rude'),('nigger','part','rude'),('nigga','part','rude'),
  ('whore','part','rude'),('slut','part','rude'),('penis','part','rude'),
  ('vagina','part','rude'),('pornhub','part','rude'),('pussy','part','rude'),
  ('dildo','part','rude'),('boobs','part','rude'),('hitler','part','rude'),
  ('retard','part','rude'),('jizz','part','rude'),
  ('faggot','part','rude'),('dickhead','part','rude'),('shithead','part','rude'),
  ('bullshit','part','rude'),('terrorist','part','rude'),('motherf','part','rude'),
  -- English, only as a whole word
  ('shit','word','rude'),('dick','word','rude'),('cock','word','rude'),
  ('sex','word','rude'),('sexy','word','rude'),('rape','word','rude'),
  ('rapist','word','rude'),('nazi','word','rude'),('fag','word','rude'),
  ('prick','word','rude'),('tit','word','rude'),('tits','word','rude'),
  ('anal','word','rude'),('anus','word','rude'),('cum','word','rude'),
  ('wank','word','rude'),('wanker','word','rude'),('pedo','word','rude'),
  ('kkk','word','rude'),('fuk','word','rude'),('ass','word','rude'),
  ('porn','word','rude'),('porno','word','rude'),('boob','word','rude'),('twat','word','rude'),
  -- Hindi and Marathi, written in English letters, anywhere in the name
  ('madarchod','part','rude'),('maderchod','part','rude'),('madarchot','part','rude'),
  ('behenchod','part','rude'),('bhenchod','part','rude'),('bhanchod','part','rude'),
  ('chutiya','part','rude'),('chutiy','part','rude'),('bhosd','part','rude'),
  ('bhosad','part','rude'),('gaandu','part','rude'),
  ('gaand','part','rude'),('jhaat','part','rude'),('jhant','part','rude'),
  ('lavde','part','rude'),('lawde','part','rude'),('chodu','part','rude'),
  ('bhadwa','part','rude'),('bhadwe','part','rude'),('bhadve','part','rude'),
  ('harami','part','rude'),('haraami','part','rude'),('zavadya','part','rude'),
  ('zhavadya','part','rude'),('bhikarchot','part','rude'),
  -- Hindi and Marathi, only as a whole word
  ('chut','word','rude'),('chod','word','rude'),('gandu','word','rude'),('randi','word','rude'),
  ('lund','word','rude'),('lauda','word','rude'),('loda','word','rude'),
  ('lavda','word','rude'),('laude','word','rude'),('lodu','word','rude'),
  ('bsdk','word','rude'),('mkc','word','rude'),('bkl','word','rude'),
  -- names that pretend to be the game or its staff
  ('wordvibe','part','reserved'),('administrator','part','reserved'),
  ('moderator','part','reserved'),('admin','word','reserved'),
  ('mod','word','reserved'),('staff','word','reserved'),
  ('support','word','reserved'),('official','word','reserved'),
  ('system','word','reserved'),('root','word','reserved')
on conflict (word) do update set how = excluded.how, reason = excluded.reason;


-- Returns null when a name is fine, otherwise 'NAME_NOT_ALLOWED' (rude) or
-- 'NAME_RESERVED' (pretends to be the game or its staff).
create or replace function public.dn_name_problem(p_name text)
returns text language plpgsql stable security definer
set search_path to 'public','pg_catalog'
as $function$
declare
  v_low     text := lower(coalesce(p_name, ''));
  v_forms   text[];
  v_form    text;
  v_squash  text;
  v_squeeze text;
  v_tokens  text[];
  v_hit     text;
begin
  -- two readings of the digit 1: "sh1t" and "1und"
  v_forms := array[translate(v_low, '0134578', 'oieastb'),
                   translate(v_low, '0134578', 'oleastb')];
  foreach v_form in array v_forms loop
    v_squash  := regexp_replace(v_form, '[^a-z]', '', 'g');
    v_squeeze := regexp_replace(v_squash, '(.)\1+', '\1', 'g');
    select array_agg(t) into v_tokens
      from (select t from unnest(regexp_split_to_array(v_form, '[^a-z]+')) t where t <> ''
            union
            select regexp_replace(t, '(.)\1+', '\1', 'g')
              from unnest(regexp_split_to_array(v_form, '[^a-z]+')) t where t <> ''
            union
            select v_squash where v_squash <> '') x;

    select b.reason into v_hit
      from public.blocked_name_words b
     where (b.how = 'part' and (position(b.word in v_squash) > 0
                                or position(b.word in v_squeeze) > 0))
        or (b.how = 'word' and b.word = any(coalesce(v_tokens, '{}')))
     order by (b.reason = 'rude') desc
     limit 1;

    if v_hit = 'rude'     then return 'NAME_NOT_ALLOWED'; end if;
    if v_hit = 'reserved' then return 'NAME_RESERVED';    end if;
  end loop;
  return null;
end;
$function$;
revoke execute on function public.dn_name_problem(text) from public, anon, authenticated;


-- What the game asks before it tries to register a name, so the player gets
-- a clear message instead of a server error. Says yes or no, never which word.
create or replace function public.name_allowed(p_username text)
returns json language plpgsql stable security definer
set search_path to 'public','pg_catalog'
as $function$
declare v_problem text := public.dn_name_problem(p_username);
begin
  return json_build_object('ok', v_problem is null, 'error', v_problem);
end;
$function$;
revoke execute on function public.name_allowed(text) from public;
grant  execute on function public.name_allowed(text) to anon, authenticated;


-- The real guard. It sits on the table, so it holds for register_player, for
-- any future rename, and for anything else that writes a username.
create or replace function public.dn_players_name_guard()
returns trigger language plpgsql security definer
set search_path to 'public','pg_catalog'
as $function$
declare v_problem text;
begin
  if tg_op = 'UPDATE' and new.username is not distinct from old.username then
    return new;
  end if;
  v_problem := public.dn_name_problem(new.username);
  if v_problem is not null then
    raise exception using errcode = '22023', message = v_problem,
      hint = 'Pick a different username.';
  end if;
  return new;
end;
$function$;
revoke execute on function public.dn_players_name_guard() from public, anon, authenticated;

drop trigger if exists players_name_guard on public.players;
create trigger players_name_guard
  before insert or update of username on public.players
  for each row execute function public.dn_players_name_guard();


-- ------------------------------------------------------------ 3. the boards ---
-- Each view below is its current definition (16_tiebreak_ranking.sql,
-- 22_sprint_one_clock.sql, 03_sprint_and_powerups.sql) with two filters added
-- and "limit 100" removed. Same columns, same order, same ranking rules.
--     not coalesce(s.flagged, false)   -- flagged results stay off the boards
--     not p.hidden                     -- hidden players stay off the boards

create or replace view public.leaderboard_today as
 select row_number() over (
          order by s.total_points desc,
                   s.time_sec,
                   coalesce(s.time_ms, s.time_sec * 1000 + 500),
                   s.shuffles,
                   s.created_at,
                   p.username) as rank,
    p.username,
    s.total_points,
    s.word_points,
    s.time_points,
    s.streak_bonus,
    s.time_sec,
    s.words_found,
    s.words_total,
    s.solved,
    s.theme,
    s.time_ms
   from scores s
     join players p using (poornata_id)
  where s.play_date = CURRENT_DATE
    and not coalesce(s.flagged, false)
    and not p.hidden
  order by 1;

create or replace view public.leaderboard_week as
 select row_number() over (
          order by sum(s.total_points) desc,
                   min(s.time_sec),
                   min(coalesce(s.time_ms, s.time_sec * 1000 + 500)),
                   p.username) as rank,
    p.username,
    sum(s.total_points)::integer as total_points,
    count(*)::integer as games_played,
    count(*) filter (where s.solved)::integer as games_solved,
    min(s.time_sec) as best_time
   from scores s
     join players p using (poornata_id)
  where s.play_date >= date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)::date
    and not coalesce(s.flagged, false)
    and not p.hidden
  group by p.username
  order by 1;

create or replace view public.leaderboard_alltime as
 with agg as (
   select scores.poornata_id,
      sum(scores.total_points)::integer as total_points,
      count(*)::integer as games_played,
      count(*) filter (where scores.solved)::integer as games_solved,
      min(scores.time_sec) filter (where scores.solved) as best_time,
      min(coalesce(scores.time_ms, scores.time_sec * 1000 + 500))
        filter (where scores.solved) as best_time_ms,
      max(scores.play_date) as last_played
     from scores
    where not coalesce(scores.flagged, false)
    group by scores.poornata_id
 )
 select row_number() over (
          order by a.total_points desc,
                   a.games_solved desc,
                   a.best_time,
                   a.best_time_ms,
                   p.username) as rank,
    p.username,
    a.total_points,
    a.games_played,
    a.games_solved,
    a.best_time,
    a.last_played
   from agg a
     join players p using (poornata_id)
  where not p.hidden
  order by 1;

create or replace view public.leaderboard_sprint_today as
select
  rank() over (order by s.puzzles_cleared desc, s.words_found desc, s.duration_sec asc) as rank,
  p.username,
  s.puzzles_cleared,
  s.words_found,
  s.duration_sec,
  s.powerups_used,
  s.flagged
from public.sprint_scores s
join public.players p using (poornata_id)
where s.play_date = current_date
  and not coalesce(s.flagged, false)
  and not p.hidden;

create or replace view public.leaderboard_sprint_week as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,
                        sum(s.words_found)     desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)                                  as best_run,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
where s.play_date >= date_trunc('week', current_date)::date
  and s.duration_sec <= 300
  and not coalesce(s.flagged, false)
  and not p.hidden
group by p.username
order by 1;

create or replace view public.leaderboard_sprint_alltime as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,
                        sum(s.words_found)     desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)                                  as best_run,
  max(s.play_date)                                        as last_played,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
where s.duration_sec <= 300
  and not coalesce(s.flagged, false)
  and not p.hidden
group by p.username
order by 1;

grant select on public.leaderboard_today, public.leaderboard_week, public.leaderboard_alltime,
                public.leaderboard_sprint_today, public.leaderboard_sprint_week,
                public.leaderboard_sprint_alltime to anon, authenticated;


-- ------------------------------------------------------------- 4. indexes ---
create index if not exists scores_play_date_idx        on public.scores (play_date);
create index if not exists sprint_scores_play_date_idx on public.sprint_scores (play_date);

commit;


-- ------------------------------------------------------------- checklist ---
select n as "#", check_name, expected, actual,
       case when check_name like '%(info)' then null else (expected = actual) end as ok
  from (

  select 1 as n, 'players has a hidden column' as check_name, 'true' as expected,
         exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'players'
                    and column_name = 'hidden')::text as actual

  union all
  select 2, 'rude and fake-staff names are stopped', 'all 12 stopped',
         (select case when count(*) filter (where public.dn_name_problem(t) is not null) = 12
                      then 'all 12 stopped'
                      else 'let through: ' || string_agg(t, ', ') filter (where public.dn_name_problem(t) is null) end
            from unnest(array['fuck_you','Sh1t head','b1tch','FUUUCK','big dick','madarchod',
                              'bh0sdike','l_u_n_d','Admin','Word Vibe','WordVibe_Mod','nigga99']) t)

  union all
  select 3, 'ordinary names are let through', 'all 19 allowed',
         (select case when count(*) filter (where public.dn_name_problem(t) is null) = 19
                      then 'all 19 allowed'
                      else 'stopped: ' || string_agg(t, ', ') filter (where public.dn_name_problem(t) is not null) end
            from unnest(array['Priya','Ashita','Nazia 07','Dickens','Essex Lad','Badminton Ace',
                              'Grace Park','Brandi','Claude','Night Owl','Hancock','Therapist Tom',
                              'Nigam','Class Act','Poornima','Boobalan','Atwater','Pournima 21','Gandule']) t)

  union all
  select 4, 'the name guard sits on the players table', 'true',
         exists (select 1 from pg_trigger
                  where tgrelid = 'public.players'::regclass
                    and tgname = 'players_name_guard' and not tgisinternal)::text

  union all
  select 5, 'public key: can ask name_allowed / cannot call the rest / cannot read the word list',
         'true / false / false',
         has_function_privilege('anon', 'public.name_allowed(text)', 'EXECUTE')::text || ' / ' ||
         has_function_privilege('anon', 'public.dn_name_problem(text)', 'EXECUTE')::text || ' / ' ||
         has_table_privilege('anon', 'public.blocked_name_words', 'SELECT')::text

  union all
  select 6, 'flagged results on any board', '0',
         ((select count(*) from public.scores s join public.players p using (poornata_id)
            join public.leaderboard_today b on b.username = p.username
           where s.play_date = current_date and s.flagged)
        + (select count(*) from public.leaderboard_sprint_today    where flagged)
        + (select count(*) from public.leaderboard_sprint_week     where flagged)
        + (select count(*) from public.leaderboard_sprint_alltime  where flagged))::text

  union all
  select 7, 'hidden players on any board', '0',
         (select count(*) from public.players p
           where p.hidden and p.username in (
                 select username from public.leaderboard_today
           union select username from public.leaderboard_week
           union select username from public.leaderboard_alltime
           union select username from public.leaderboard_sprint_today
           union select username from public.leaderboard_sprint_week
           union select username from public.leaderboard_sprint_alltime))::text

  union all
  select 8, 'boards have no row limit inside the view', 'none capped',
         coalesce((select string_agg(c.relname, ', ') from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname like 'leaderboard\_%'
                     and pg_get_viewdef(c.oid) ~* '\mlimit\M'), 'none capped')

  union all
  select 9, 'existing players whose name the new check would stop (info)', '0',
         (select count(*)::text from public.players where public.dn_name_problem(username) is not null)

  union all
  select 10, 'play_date indexes on scores and sprint_scores', 'true',
         (to_regclass('public.scores_play_date_idx') is not null
          and to_regclass('public.sprint_scores_play_date_idx') is not null)::text

  union all
  select 11, 'players today on the board / flagged today, now off it (info)', 'numbers',
         (select count(*) from public.leaderboard_today)::text || ' / ' ||
         (select count(*) from public.scores where play_date = current_date and flagged)::text

) c
order by n;

-- Check 9 above counts existing names the new rule would stop. To see them:
-- select username from public.players where public.dn_name_problem(username) is not null;
-- Then hide each one from the admin console (Players tab, "Hide a player").
