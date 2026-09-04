create table if not exists public.meter_change_controls (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  meter_id uuid not null references public.meters(id) on delete cascade,
  change_type text not null check (change_type in ('contracted_power','power_factor','tariff','supply_deactivation')),
  effective_period date not null,
  status text not null default 'applied' check (status in ('planned','applied','verified','cancelled')),
  previous_value text,
  new_value text,
  details jsonb not null default '{}'::jsonb,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists meter_change_controls_meter_period_idx
  on public.meter_change_controls(meter_id, effective_period desc);

alter table public.meter_change_controls enable row level security;

create policy "members read meter controls"
on public.meter_change_controls for select to authenticated
using (exists (
  select 1 from public.organization_members om
  where om.organization_id = meter_change_controls.organization_id
    and om.user_id = (select auth.uid())
));

create policy "members create meter controls"
on public.meter_change_controls for insert to authenticated
with check (
  created_by = (select auth.uid()) and exists (
    select 1 from public.organization_members om
    where om.organization_id = meter_change_controls.organization_id
      and om.user_id = (select auth.uid())
  )
);

create policy "members update meter controls"
on public.meter_change_controls for update to authenticated
using (exists (
  select 1 from public.organization_members om
  where om.organization_id = meter_change_controls.organization_id
    and om.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.organization_members om
  where om.organization_id = meter_change_controls.organization_id
    and om.user_id = (select auth.uid())
));

create policy "members delete meter controls"
on public.meter_change_controls for delete to authenticated
using (exists (
  select 1 from public.organization_members om
  where om.organization_id = meter_change_controls.organization_id
    and om.user_id = (select auth.uid())
));

grant select, insert, update, delete on public.meter_change_controls to authenticated;
