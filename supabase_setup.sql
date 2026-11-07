-- 사전증여 처방전 · 상담 신청 접수 표
-- Supabase 대시보드 → SQL Editor → 새 쿼리에 전체 붙여넣고 Run

create table if not exists public.consult_requests (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 1 and 40),
  phone       text not null check (phone ~ '^[0-9+\- ]{9,20}$'),
  memo        text check (memo is null or char_length(memo) <= 1000),
  consent     boolean not null check (consent),          -- 개인정보 수집 동의(필수)
  inputs      jsonb not null,                             -- 입력값 (재산·배우자·자녀 수 등)
  result      jsonb not null,                             -- 계산 결과 (예상 상속세·추천 증여액 등)
  summary     text check (summary is null or char_length(summary) <= 2000),  -- 사람이 읽는 요약
  page_url    text check (page_url is null or char_length(page_url) <= 500),
  status      text not null default '접수'                -- 접수 / 연락완료 / 상담완료 (직접 수정)
);

-- 보안: 웹페이지(anon 키)는 "새 신청 넣기"만 가능, 읽기·수정·삭제는 불가
alter table public.consult_requests enable row level security;

drop policy if exists "anon insert only" on public.consult_requests;
create policy "anon insert only"
  on public.consult_requests
  for insert to anon
  with check (consent = true and status = '접수');

revoke all on public.consult_requests from anon;
grant insert (name, phone, memo, consent, inputs, result, summary, page_url)
  on public.consult_requests to anon;

-- 접수 목록은 대시보드 → Table Editor → consult_requests 에서 확인합니다.
