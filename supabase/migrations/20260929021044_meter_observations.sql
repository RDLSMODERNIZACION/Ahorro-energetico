create table public.meter_observations (
  meter_id uuid primary key references public.meters(id) on delete cascade,
  observation text not null check (char_length(btrim(observation)) between 1 and 2000),
  updated_at timestamptz not null default now()
);
alter table public.meter_observations enable row level security;
revoke all on public.meter_observations from anon;
grant select, insert, update, delete on public.meter_observations to authenticated, service_role;
create policy observations_read on public.meter_observations for select to authenticated using (exists (select 1 from public.meters mt join public.organization_members member on member.organization_id = mt.organization_id where mt.id = meter_observations.meter_id and member.user_id = (select auth.uid())));
create policy observations_insert on public.meter_observations for insert to authenticated with check (exists (select 1 from public.meters mt join public.organization_members member on member.organization_id = mt.organization_id where mt.id = meter_observations.meter_id and member.user_id = (select auth.uid()) and member.role in ('admin', 'analyst')));
create policy observations_update on public.meter_observations for update to authenticated using (exists (select 1 from public.meters mt join public.organization_members member on member.organization_id = mt.organization_id where mt.id = meter_observations.meter_id and member.user_id = (select auth.uid()) and member.role in ('admin', 'analyst'))) with check (exists (select 1 from public.meters mt join public.organization_members member on member.organization_id = mt.organization_id where mt.id = meter_observations.meter_id and member.user_id = (select auth.uid()) and member.role in ('admin', 'analyst')));
create policy observations_delete on public.meter_observations for delete to authenticated using (exists (select 1 from public.meters mt join public.organization_members member on member.organization_id = mt.organization_id where mt.id = meter_observations.meter_id and member.user_id = (select auth.uid()) and member.role in ('admin', 'analyst')));
