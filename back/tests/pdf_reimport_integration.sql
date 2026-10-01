-- Integration assertions. All fixture writes roll back; run after pdf_invoice_import.sql.
begin;
do $test$
declare
  org uuid;
  batch uuid;
  meter uuid;
  light uuid;
  data jsonb;
  result jsonb;
  inv uuid;
  n integer;
  total numeric;
begin
  select m.id,m.organization_id into meter,org from public.meters m
    where exists(select 1 from public.import_batches b where b.organization_id=m.organization_id)
    and exists(select 1 from public.public_lighting_meters l where l.organization_id=m.organization_id) limit 1;
  assert meter is not null, 'Integration test needs an organization with a meter, lighting meter and import batch';
  select id into batch from public.import_batches where organization_id=org limit 1;
  data := jsonb_build_object('invoice',jsonb_build_object('invoice_number','0000-999999999901','provider','EPEN',
    'billing_period','2099-01-01','period_start','2098-12-01','period_end','2098-12-31',
    'current_tariff_code','T2','contracted_kw_peak',26,'subtotal',2132666.2,'taxes',639799.86,'total_amount',2772466.06,'validation_status','valid','raw_data','{}'::jsonb),
    'measurements',jsonb_build_array(jsonb_build_object('time_band','all','register_sequence',1,'measurement_type','summary',
      'meter_number','19676972','active_energy_kwh',2117,'reactive_energy_kvarh',884,'demand_kw',22.2,'registered_demand_peak_kw',22,
      'tangent_phi',0.42,'power_factor',0.9228,'reactive_surcharge_percent',2.25)), 'lines','[]'::jsonb);
  result := public.import_epen_pdf(org,batch,meter,null,data);
  assert result->>'status'='imported',result::text;
  inv := (result->>'invoice_id')::uuid;
  delete from public.invoice_measurements where invoice_id=inv;
  result := public.import_epen_pdf(org,batch,meter,null,data);
  assert result->>'status'='updated',result::text;
  select sum(active_energy_kwh),count(*) into total,n from public.invoice_measurements where invoice_id=inv;
  assert total=2117 and n=1,'Missing measurements not repaired';
  result := public.import_epen_pdf(org,batch,meter,null,data);
  assert result->>'status'='duplicate',result::text;
  update public.invoice_measurements set active_energy_kwh=null where invoice_id=inv;
  update public.invoices set contracted_kw_peak=null where id=inv;
  result := public.import_epen_pdf(org,batch,meter,null,data);
  assert result->>'status'='updated',result::text;
  select sum(active_energy_kwh) into total from public.invoice_measurements where invoice_id=inv;
  assert total=2117,'Partial repair doubled consumption';
  assert (select contracted_kw_peak=26 from public.invoices where id=inv),'Missing contracted power not repaired';
  select sum(reactive_energy_kvarh) into total from public.invoice_measurements where invoice_id=inv;
  assert total=884,'Partial repair doubled reactive energy';
  update public.invoice_measurements set active_energy_kwh=0 where invoice_id=inv and active_energy_kwh is not null;
  result := public.import_epen_pdf(org,batch,meter,null,data);
  assert result->>'status'='duplicate','Real zero must be preserved';
  result := public.import_epen_pdf(org,batch,meter,null,jsonb_set(data,'{invoice,total_amount}','1'));
  assert result->>'status'='conflict','Conflicting amount accepted';
  result := public.import_epen_pdf(org,batch,gen_random_uuid(),null,data);
  assert result->>'status'='conflict','Wrong supply accepted';
  select id into light from public.public_lighting_meters where organization_id=org limit 1;
  data := jsonb_set(data,'{invoice,invoice_number}','"0000-999999999902"');
  result := public.import_epen_pdf(org,batch,null,light,data);
  assert result->>'status'='imported',result::text;
  inv := (result->>'invoice_id')::uuid;
  update public.public_lighting_invoices set active_energy_kwh=null where id=inv;
  result := public.import_epen_pdf(org,batch,null,light,data);
  assert result->>'status'='updated',result::text;
  assert (select active_energy_kwh=2117 from public.public_lighting_invoices where id=inv),'Lighting missing kWh not repaired';
  result := public.import_epen_pdf(org,batch,null,light,data);
  assert result->>'status'='duplicate',result::text;
end;
$test$;

rollback;

