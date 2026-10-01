-- Atomic per-invoice import; callable only by the trusted backend after require_org.
alter table public.import_batches add column if not exists result jsonb;
create or replace function public.import_epen_pdf(p_org uuid, p_batch uuid, p_meter uuid, p_lighting uuid, p_data jsonb)
returns jsonb language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v public.invoices%rowtype;
  m public.invoice_measurements%rowtype;
  l public.invoice_lines%rowtype;
  old_record record;
  new_id uuid;
  item jsonb;
  matches integer := 0;
  target_id uuid;
  target_meter uuid;
  target_kind text;
  field_name text;
  field_present boolean;
  patch jsonb := '{}'::jsonb;
  before_row jsonb;
  changed boolean := false;
begin
  if not exists(select 1 from public.import_batches where id=p_batch and organization_id=p_org) then
    raise exception 'Lote ajeno a la organización';
  end if;
  v := jsonb_populate_record(null::public.invoices, p_data->'invoice');
  if v.invoice_number is null or v.billing_period is null or v.total_amount is null or v.provider <> 'EPEN' then
    raise exception 'Factura incompleta';
  end if;
  -- Serializes imports of the same number across both invoice tables.
  perform pg_advisory_xact_lock(hashtextextended('EPEN:' || v.invoice_number, 0));
  for old_record in
    select id,meter_id as supply_id,'dependencias' as kind,invoice_number,billing_period,total_amount from public.invoices where organization_id=p_org and provider='EPEN' and invoice_number=v.invoice_number
    union all
    select id,public_lighting_meter_id as supply_id,'alumbrado' as kind,invoice_number,billing_period,total_amount from public.public_lighting_invoices where organization_id=p_org and invoice_number=v.invoice_number
  loop
    matches := matches + 1;
    target_id := old_record.id;
    target_meter := old_record.supply_id;
    target_kind := old_record.kind;
    if old_record.billing_period is distinct from v.billing_period or old_record.total_amount is distinct from v.total_amount then
      return jsonb_build_object('status','conflict','message','La factura ya existe con otro período o importe. No se reemplazó.');
    end if;
  end loop;
  if matches > 1 then
    return jsonb_build_object('status','conflict','message','Existen varios registros con ese número. Requiere revisión.');
  end if;
  if matches = 1 then
    if (target_kind='dependencias' and (p_lighting is not null or target_meter is distinct from p_meter))
       or (target_kind='alumbrado' and target_meter is distinct from p_lighting) then
      return jsonb_build_object('status','conflict','message','El número ya existe en otro suministro. Requiere revisión.');
    end if;
    -- A parsed PDF carries one summary. Never add its totals over existing register values.
    if jsonb_array_length(p_data->'measurements') is distinct from 1 then
      raise exception 'Se requiere un resumen de mediciones por PDF';
    end if;
    item := p_data->'measurements'->0;
    if target_kind='dependencias' then
      perform 1 from public.invoices where id=target_id for update;
      perform 1 from public.invoice_measurements where invoice_id=target_id for update;
      foreach field_name in array array['active_energy_kwh','reactive_energy_kvarh','demand_kw',
        'registered_demand_peak_kw','registered_demand_off_peak_kw','tangent_phi','power_factor',
        'reactive_surcharge_percent','prior_year_energy_kwh'] loop
        select exists(select 1 from public.invoice_measurements x where x.invoice_id=target_id
          and to_jsonb(x)->>field_name is not null) into field_present;
        if not field_present and item->>field_name is not null then
          patch := patch || jsonb_build_object(field_name,item->field_name);
        end if;
      end loop;
      if patch <> '{}'::jsonb then
        -- Supplement only missing dimensions. Existing values, including real zeroes, are preserved.
        m := jsonb_populate_record(null::public.invoice_measurements, patch || jsonb_build_object(
          'time_band','all','measurement_type','summary','meter_number',item->'meter_number',
          'reading_start',item->'reading_start','reading_end',item->'reading_end'));
        insert into public.invoice_measurements(invoice_id,time_band,register_sequence,measurement_type,
          meter_number,active_energy_kwh,reactive_energy_kvarh,demand_kw,registered_demand_peak_kw,
          registered_demand_off_peak_kw,tangent_phi,power_factor,reactive_surcharge_percent,
          prior_year_energy_kwh,reading_start,reading_end)
        select target_id,'all',coalesce(max(register_sequence),0)+1,'summary',m.meter_number,
          m.active_energy_kwh,m.reactive_energy_kvarh,m.demand_kw,m.registered_demand_peak_kw,
          m.registered_demand_off_peak_kw,m.tangent_phi,m.power_factor,m.reactive_surcharge_percent,
          m.prior_year_energy_kwh,m.reading_start,m.reading_end
        from public.invoice_measurements where invoice_id=target_id;
        changed := true;
      end if;
      select to_jsonb(x) into before_row from public.invoices x where id=target_id;
      foreach field_name in array array['contracted_kw_peak','contracted_kw_off_peak','current_tariff_code',
        'period_start','period_end','issue_date','due_date','raw_text','net_taxable','vat_amount',
        'vat_perception_amount','municipal_tax_amount'] loop
        if before_row->>field_name is null and p_data->'invoice'->>field_name is not null then
          execute format('update public.invoices set %1$I=(jsonb_populate_record(null::public.invoices,$1)).%1$I where id=$2',field_name)
            using p_data->'invoice',target_id;
          changed := true;
        end if;
      end loop;
      if v.document_path is not null and (before_row->>'document_path' is null
          or before_row->>'document_path' like 'pending-storage/%%') then
        update public.invoices set document_path=v.document_path,document_hash=v.document_hash where id=target_id;
        changed := true;
      end if;
      if not exists(select 1 from public.invoice_lines where invoice_id=target_id) then
        for item in select value from jsonb_array_elements(p_data->'lines') loop
          l := jsonb_populate_record(null::public.invoice_lines,item);
          insert into public.invoice_lines(invoice_id,concept_code,description,quantity,unit_price,net_amount,line_number,is_penalty)
          values(target_id,l.concept_code,l.description,l.quantity,l.unit_price,l.net_amount,l.line_number,l.is_penalty);
          changed := true;
        end loop;
      end if;
      if changed then update public.invoices set updated_at=now() where id=target_id; end if;
    else
      select to_jsonb(x) into before_row from public.public_lighting_invoices x where id=target_id for update;
      patch := item || jsonb_build_object('reading_start',v.period_start,'reading_end',v.period_end,
        'issue_date',v.issue_date,'tariff_code',v.current_tariff_code,'voltage_level',v.voltage_level);
      foreach field_name in array array['active_energy_kwh','reactive_energy_kvarh','tangent_phi',
        'reactive_surcharge_percent','meter_number','reading_start','reading_end','issue_date',
        'tariff_code','voltage_level'] loop
        if before_row->>field_name is null and patch->>field_name is not null then
          execute format('update public.public_lighting_invoices set %1$I=(jsonb_populate_record(null::public.public_lighting_invoices,$1)).%1$I where id=$2',field_name)
            using patch,target_id;
          changed := true;
        end if;
      end loop;
      if v.document_path is not null and (before_row->>'source_file' is null
          or before_row->>'source_file' like 'pending-storage/%%') then
        update public.public_lighting_invoices set source_file=v.document_path where id=target_id;
        changed := true;
      end if;
      if changed then update public.public_lighting_invoices set updated_at=now() where id=target_id; end if;
    end if;
    return jsonb_build_object('status',case when changed then 'updated' else 'duplicate' end,
      'invoice_id',target_id,'message',case when changed then 'Se completaron los datos faltantes sin duplicar la factura.'
      else 'Factura revisada; no se encontraron datos faltantes.' end);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text || ':' || coalesce(p_lighting,p_meter)::text || ':' || v.billing_period::text, 0));
  if p_lighting is not null then
    if not exists(select 1 from public.public_lighting_meters where id=p_lighting and organization_id=p_org) then raise exception 'Suministro de alumbrado inválido'; end if;
    if exists(select 1 from public.public_lighting_invoices where public_lighting_meter_id=p_lighting and billing_period=v.billing_period) then
      return jsonb_build_object('status','conflict','message','El suministro ya tiene otra factura en ese período. Requiere revisión.');
    end if;
    m := jsonb_populate_record(null::public.invoice_measurements, p_data->'measurements'->0);
    insert into public.public_lighting_invoices(organization_id,public_lighting_meter_id,invoice_number,billing_period,reading_start,reading_end,issue_date,meter_number,tariff_code,voltage_level,active_energy_kwh,reactive_energy_kvarh,tangent_phi,reactive_surcharge_percent,total_amount,source_file,validation_status,metadata)
    values(p_org,p_lighting,v.invoice_number,v.billing_period,v.period_start,v.period_end,v.issue_date,m.meter_number,v.current_tariff_code,v.voltage_level,m.active_energy_kwh,m.reactive_energy_kvarh,m.tangent_phi,m.reactive_surcharge_percent,v.total_amount,v.document_path,'verified_from_pdf',jsonb_build_object('import_batch_id',p_batch,'invoice',p_data->'invoice','lines',p_data->'lines','measurement',p_data->'measurements'->0)) returning id into new_id;
  else
    if not exists(select 1 from public.meters where id=p_meter and organization_id=p_org) then raise exception 'Suministro inválido'; end if;
    if exists(select 1 from public.invoices where meter_id=p_meter and billing_period=v.billing_period) then
      return jsonb_build_object('status','conflict','message','El suministro ya tiene otra factura en ese período. Requiere revisión.');
    end if;
    insert into public.invoices(organization_id,meter_id,import_batch_id,invoice_number,provider,billing_period,period_start,period_end,issue_date,due_date,current_tariff_code,voltage_level,contracted_kw_peak,subtotal,net_taxable,vat_amount,vat_perception_amount,municipal_tax_amount,taxes,total_amount,amount_due,service_code,contract_number,document_hash,document_path,raw_text,validation_status,raw_data) values(p_org,p_meter,p_batch,v.invoice_number,v.provider,v.billing_period,v.period_start,v.period_end,v.issue_date,v.due_date,v.current_tariff_code,v.voltage_level,v.contracted_kw_peak,v.subtotal,v.net_taxable,v.vat_amount,v.vat_perception_amount,v.municipal_tax_amount,v.taxes,v.total_amount,v.amount_due,v.service_code,v.contract_number,v.document_hash,v.document_path,v.raw_text,v.validation_status,v.raw_data) returning id into new_id;
    for item in select value from jsonb_array_elements(p_data->'measurements') loop
      m := jsonb_populate_record(null::public.invoice_measurements,item);
      insert into public.invoice_measurements(invoice_id,time_band,register_sequence,measurement_type,meter_number,active_energy_kwh,reactive_energy_kvarh,demand_kw,registered_demand_peak_kw,tangent_phi,power_factor,reactive_surcharge_percent,reading_start,reading_end,reading_previous,reading_current) values(new_id,m.time_band,m.register_sequence,m.measurement_type,m.meter_number,m.active_energy_kwh,m.reactive_energy_kvarh,m.demand_kw,m.registered_demand_peak_kw,m.tangent_phi,m.power_factor,m.reactive_surcharge_percent,m.reading_start,m.reading_end,m.reading_previous,m.reading_current);
    end loop;
    for item in select value from jsonb_array_elements(p_data->'lines') loop
      l := jsonb_populate_record(null::public.invoice_lines,item);
      insert into public.invoice_lines(invoice_id,concept_code,description,quantity,unit_price,net_amount,line_number,is_penalty) values(new_id,l.concept_code,l.description,l.quantity,l.unit_price,l.net_amount,l.line_number,l.is_penalty);
    end loop;
    update public.missing_invoice_alerts set status='resolved',resolved_at=now(),resolution_note='Factura PDF incorporada' where organization_id=p_org and meter_id=p_meter and expected_period=v.billing_period and status='open';
    update public.meters set last_seen_period=greatest(last_seen_period,v.billing_period) where id=p_meter;
  end if;
  return jsonb_build_object('status','imported','invoice_id',new_id,'category',case when p_lighting is null then 'dependencias' else 'alumbrado' end);
end;
$$;
revoke all on function public.import_epen_pdf(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.import_epen_pdf(uuid,uuid,uuid,uuid,jsonb) to service_role;
