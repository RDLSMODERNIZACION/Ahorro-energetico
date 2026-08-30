-- AP COMO CLASIFICACION DEL MEDIDOR GENERAL
-- Ejecutar UNA VEZ en Supabase SQL Editor.

alter table public.public_lighting_meters
  add column if not exists meter_id uuid null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'public_lighting_meters_meter_id_fkey'
  ) then
    alter table public.public_lighting_meters
      add constraint public_lighting_meters_meter_id_fkey
      foreign key (meter_id)
      references public.meters(id)
      on delete set null;
  end if;
end $$;

create index if not exists idx_public_lighting_meters_meter_id
  on public.public_lighting_meters(meter_id);

-- 1) Vincular por número de suministro cuando coincide.
update public.public_lighting_meters pl
set meter_id = m.id
from public.meters m
where pl.meter_id is null
  and m.organization_id = pl.organization_id
  and coalesce(trim(pl.supply_number), '') <> ''
  and trim(coalesce(m.supply_number, '')) = trim(pl.supply_number);

-- 2) Para los restantes, vincular por número de medidor.
update public.public_lighting_meters pl
set meter_id = m.id
from public.meters m
where pl.meter_id is null
  and m.organization_id = pl.organization_id
  and coalesce(trim(pl.meter_number), '') <> ''
  and trim(coalesce(m.meter_number, '')) = trim(pl.meter_number);

-- Diagnóstico: estos deberían quedar en 0 o ser revisados manualmente.
select
  id,
  supply_number,
  meter_number,
  address
from public.public_lighting_meters
where meter_id is null
order by supply_number;
