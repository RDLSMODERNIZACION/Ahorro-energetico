-- EPEN - Resolucion Ministerial 041/2026
-- Periodo de facturacion agosto 2026, consumos julio 2026.
-- Valores sin IVA ni otros tributos.

insert into public.tariff_categories
  (provider, code, name, description, min_capacity_kw, max_capacity_kw, active)
values
  ('EPEN','T1G','Pequena demanda general G1','Hasta 250 kWh/mes y potencia inferior a 10 kW',0,10,true),
  ('EPEN','T1G2','Pequena demanda general G2','Mas de 250 y hasta 1000 kWh/mes; potencia inferior a 10 kW',0,10,true),
  ('EPEN','T1G3','Pequena demanda general G3','Mas de 1000 y hasta 2000 kWh/mes; potencia inferior a 10 kW',0,10,true),
  ('EPEN','T1G4','Pequena demanda general G4','Mas de 2000 kWh/mes; potencia inferior a 10 kW',0,10,true),
  ('EPEN','T1-AP','Alumbrado publico','Potencia inferior a 10 kW',0,10,true),
  ('EPEN','T2','Medianas demandas','Desde 10 kW e inferior a 50 kW',10,50,true),
  ('EPEN','T3','Grandes demandas','Desde 50 kW e inferior a 300 kW',50,300,true),
  ('EPEN','T3A','Grandes demandas de 300 kW o mas','Tramo general para capacidades iguales o superiores a 300 kW',300,null,true),
  ('EPEN','T4-MT','Grandes demandas especiales - MT','Capacidad igual o superior a 100 kW',100,null,true),
  ('EPEN','T4-AT','Grandes demandas especiales - AT','Capacidad igual o superior a 100 kW',100,null,true),
  ('EPEN','T4-CD','Grandes demandas especiales - CD','Capacidad igual o superior a 100 kW',100,null,true)
on conflict (provider,code) do update set
  name=excluded.name,
  description=excluded.description,
  min_capacity_kw=excluded.min_capacity_kw,
  max_capacity_kw=excluded.max_capacity_kw,
  active=excluded.active;

insert into public.tariff_schedules
  (provider,resolution_number,consumption_month,billing_month,valid_from,valid_to,currency,excludes_taxes,source_document_path,source_document_hash,notes)
values
  ('EPEN','041/2026','2026-07-01','2026-08-01','2026-07-01','2026-07-31','ARS',true,
   'CT-Consumos-07-2026.pdf','3af8de79f6f20d1778121093a4a1731472257c1102de9eba3ba8a5a2c6e26ff1',
   'Cuadro tarifario oficial. Facturacion agosto 2026 por consumos de julio 2026. Valores sin impuestos.')
on conflict (provider,resolution_number,consumption_month) do update set
  billing_month=excluded.billing_month,
  valid_from=excluded.valid_from,
  valid_to=excluded.valid_to,
  currency=excluded.currency,
  excludes_taxes=excluded.excludes_taxes,
  source_document_path=excluded.source_document_path,
  source_document_hash=excluded.source_document_hash,
  notes=excluded.notes;

delete from public.tariff_rates
where schedule_id=(select id from public.tariff_schedules where provider='EPEN' and resolution_number='041/2026' and consumption_month='2026-07-01');

with schedule as (
  select id from public.tariff_schedules
  where provider='EPEN' and resolution_number='041/2026' and consumption_month='2026-07-01'
), rates(code,voltage,segment,min_kw,max_kw,min_kwh,max_kwh,charge_code,charge_name,unit,time_band,price) as (
  values
  ('T1G','NA','general',0,10,0,250,'CFI','Cargo fijo','ARS_MONTH','all',18569.08),
  ('T1G','NA','general',0,10,0,250,'ECO','Energia','ARS_KWH','all',494.805),
  ('T1G2','NA','general',0,10,250,1000,'CFI','Cargo fijo','ARS_MONTH','all',51087.65),
  ('T1G2','NA','general',0,10,250,1000,'ECO','Energia','ARS_KWH','all',419.011),
  ('T1G3','NA','general',0,10,1000,2000,'CFI','Cargo fijo','ARS_MONTH','all',98507.89),
  ('T1G3','NA','general',0,10,1000,2000,'ECO','Energia','ARS_KWH','all',380.222),
  ('T1G4','NA','general',0,10,2000,null,'CFI','Cargo fijo','ARS_MONTH','all',166970.94),
  ('T1G4','NA','general',0,10,2000,null,'ECO','Energia','ARS_KWH','all',374.997),
  ('T1-AP','NA','alumbrado_publico',0,10,null,null,'ECO','Energia alumbrado publico','ARS_KWH','all',515.398),

  ('T2','BT','general',10,50,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',50053.84),
  ('T2','BT','general',10,50,null,null,'ECO','Energia','ARS_KWH','all',396.239),
  ('T2','MT','general',10,50,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',25664.70),
  ('T2','MT','general',10,50,null,null,'ECO','Energia','ARS_KWH','all',348.325),

  ('T3','BT','general',50,300,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',57656.55),
  ('T3','BT','general',50,300,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',44472.05),
  ('T3','BT','general',50,300,null,null,'ERE','Energia restante','ARS_KWH','remaining',353.193),
  ('T3','BT','general',50,300,null,null,'EVA','Energia valle','ARS_KWH','valley',348.955),
  ('T3','BT','general',50,300,null,null,'EPI','Energia pico','ARS_KWH','peak',361.414),
  ('T3','MT','general',50,300,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',28746.42),
  ('T3','MT','general',50,300,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',23953.92),
  ('T3','MT','general',50,300,null,null,'ERE','Energia restante','ARS_KWH','remaining',324.624),
  ('T3','MT','general',50,300,null,null,'EVA','Energia valle','ARS_KWH','valley',329.155),
  ('T3','MT','general',50,300,null,null,'EPI','Energia pico','ARS_KWH','peak',323.740),
  ('T3','AT','general',50,300,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',21694.45),
  ('T3','AT','general',50,300,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',20215.22),
  ('T3','AT','general',50,300,null,null,'ERE','Energia restante','ARS_KWH','remaining',248.453),
  ('T3','AT','general',50,300,null,null,'EVA','Energia valle','ARS_KWH','valley',246.356),
  ('T3','AT','general',50,300,null,null,'EPI','Energia pico','ARS_KWH','peak',253.920),

  ('T3A','BT','general',300,null,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',68626.62),
  ('T3A','BT','general',300,null,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',54427.94),
  ('T3A','BT','general',300,null,null,null,'ERE','Energia restante','ARS_KWH','remaining',346.272),
  ('T3A','BT','general',300,null,null,null,'EVA','Energia valle','ARS_KWH','valley',342.582),
  ('T3A','BT','general',300,null,null,null,'EPI','Energia pico','ARS_KWH','peak',353.838),
  ('T3A','MT','general',300,null,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',24291.44),
  ('T3A','MT','general',300,null,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',20848.30),
  ('T3A','MT','general',300,null,null,null,'ERE','Energia restante','ARS_KWH','remaining',315.722),
  ('T3A','MT','general',300,null,null,null,'EVA','Energia valle','ARS_KWH','valley',320.440),
  ('T3A','MT','general',300,null,null,null,'EPI','Energia pico','ARS_KWH','peak',322.223),
  ('T3A','AT','general',300,null,null,null,'DEP','Capacidad contratada en pico','ARS_KW_MONTH','peak',21901.31),
  ('T3A','AT','general',300,null,null,null,'DFP','Capacidad contratada fuera de pico','ARS_KW_MONTH','off_peak',20737.51),
  ('T3A','AT','general',300,null,null,null,'ERE','Energia restante','ARS_KWH','remaining',279.364),
  ('T3A','AT','general',300,null,null,null,'EVA','Energia valle','ARS_KWH','valley',280.394),
  ('T3A','AT','general',300,null,null,null,'EPI','Energia pico','ARS_KWH','peak',280.284),

  ('T4-MT','MT','special',100,300,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',32835.17),
  ('T4-MT','MT','special',100,300,null,null,'ECO','Energia','ARS_KWH','all',259.774),
  ('T4-MT','MT','special',300,null,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',28661.50),
  ('T4-MT','MT','special',300,null,null,null,'ECO','Energia','ARS_KWH','all',241.093),
  ('T4-AT','AT','special',100,300,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',31153.29),
  ('T4-AT','AT','special',100,300,null,null,'ECO','Energia','ARS_KWH','all',253.960),
  ('T4-AT','AT','special',300,null,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',28537.82),
  ('T4-AT','AT','special',300,null,null,null,'ECO','Energia','ARS_KWH','all',236.006),
  ('T4-CD','NA','special',100,300,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',19712.84),
  ('T4-CD','NA','special',100,300,null,null,'ECO','Energia','ARS_KWH','all',115.127),
  ('T4-CD','NA','special',300,null,null,null,'DEM','Capacidad contratada','ARS_KW_MONTH','all',18855.76),
  ('T4-CD','NA','special',300,null,null,null,'ECO','Energia','ARS_KWH','all',115.878)
)
insert into public.tariff_rates
  (schedule_id,category_id,voltage_level,customer_segment,min_capacity_kw,max_capacity_kw,min_consumption_kwh,max_consumption_kwh,charge_code,charge_name,unit,time_band,subsidized,unit_price,metadata)
select schedule.id,c.id,r.voltage,r.segment,r.min_kw,r.max_kw,r.min_kwh,r.max_kwh,r.charge_code,r.charge_name,r.unit,r.time_band,false,r.price,
       jsonb_build_object('source_page',case when r.code like 'T1%' then 4 when r.code='T2' then 7 when r.code in ('T3','T3A') then 8 else 10 end)
from rates r
cross join schedule
join public.tariff_categories c on c.provider='EPEN' and c.code=r.code;

update public.invoices i
set tariff_schedule_id=s.id
from public.tariff_schedules s
where i.provider='EPEN'
  and s.provider='EPEN'
  and s.resolution_number='041/2026'
  and coalesce(i.billing_period,i.period_start) between s.valid_from and s.valid_to;
