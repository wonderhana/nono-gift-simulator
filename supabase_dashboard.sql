-- 사전증여 처방전 · 이용 통계 + 관리자 대시보드 권한
-- Supabase 대시보드 → SQL Editor → 새 쿼리에 전체 붙여넣고 Run (supabase_setup.sql 다음에 실행)

-- 1) 관리자 명단: 여기 있는 이메일로 로그인한 사람만 신청·통계를 볼 수 있음
create table if not exists public.admins (email text primary key);
insert into public.admins(email) values ('taxmission903@gmail.com'), ('nono@nono.admin') on conflict do nothing;
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create or replace function public.is_admin() returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.admins where email = lower(coalesce(auth.jwt()->>'email',''))) $$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- 2) 이용 기록: 개인을 알아볼 수 없는 정보만 (이름·연락처·IP 저장 안 함)
create table if not exists public.page_events (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  session_id  text not null check (char_length(session_id) between 8 and 40),
  event       text not null check (event in ('visit','simulate','share_family','share_link','download','consult_open','consult_submit','kakao_click','youtube_click')),
  source      text check (source is null or char_length(source) <= 60),   -- 유입 경로 (youtube, kakao, google, direct …)
  device      text check (device is null or device in ('mobile','desktop')),
  estate_band text check (estate_band is null or char_length(estate_band) <= 20),
  children    smallint check (children is null or children between 0 and 20),
  spouse      boolean
);
create index if not exists page_events_created_idx on public.page_events (created_at);
alter table public.page_events enable row level security;

drop policy if exists "anon insert events" on public.page_events;
create policy "anon insert events" on public.page_events for insert to anon with check (true);
revoke all on public.page_events from anon;
grant insert (session_id, event, source, device, estate_band, children, spouse) on public.page_events to anon;

-- 3) 관리자 권한: 신청 목록 읽기 + 진행 상태 수정, 이용 기록 읽기
drop policy if exists "admin read requests" on public.consult_requests;
create policy "admin read requests" on public.consult_requests for select to authenticated using (public.is_admin());
drop policy if exists "admin update requests" on public.consult_requests;
create policy "admin update requests" on public.consult_requests for update to authenticated using (public.is_admin()) with check (public.is_admin());
grant select on public.consult_requests to authenticated;
grant update (status) on public.consult_requests to authenticated;

drop policy if exists "admin read events" on public.page_events;
create policy "admin read events" on public.page_events for select to authenticated using (public.is_admin());
grant select on public.page_events to authenticated;

-- 4) 통계 집계 (관리자만): 기간 안의 날짜별·이벤트별 건수와 방문자(세션) 수
create or replace function public.admin_event_stats(p_from timestamptz, p_to timestamptz)
returns table(day date, event text, n bigint, sessions bigint)
language sql stable security definer set search_path = public as
$$
  select (created_at at time zone 'Asia/Seoul')::date as day, event, count(*) as n, count(distinct session_id) as sessions
  from public.page_events
  where public.is_admin() and created_at >= p_from and created_at < p_to
  group by 1, 2 order by 1, 2
$$;
revoke all on function public.admin_event_stats(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_event_stats(timestamptz, timestamptz) to authenticated;

-- 유입 경로·기기·재산 구간별 방문 세션 수
create or replace function public.admin_breakdown(p_from timestamptz, p_to timestamptz)
returns table(dim text, val text, sessions bigint)
language sql stable security definer set search_path = public as
$$
  with v as (select * from public.page_events where public.is_admin() and created_at >= p_from and created_at < p_to)
  select 'source', coalesce(source,'direct'), count(distinct session_id) from v where event = 'visit' group by 2
  union all
  select 'device', coalesce(device,'?'), count(distinct session_id) from v where event = 'visit' group by 2
  union all
  select 'estate', estate_band, count(distinct session_id) from v where event = 'consult_open' and estate_band is not null group by 2
  order by 1, 3 desc
$$;
revoke all on function public.admin_breakdown(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_breakdown(timestamptz, timestamptz) to authenticated;
