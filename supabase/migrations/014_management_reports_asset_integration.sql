-- EPC BETHEL — Étape 5 : rapports de gestion et intégration achats/patrimoine.
-- À appliquer après les migrations 001 à 013, d'abord dans un projet Supabase de test.

begin;

-- Registre paginé côté serveur pour éviter des rapports incomplets dus aux limites REST.
create or replace function public.get_management_report_rows(
  p_report_key text,
  p_from date default null,
  p_to date default null,
  p_school_year_id uuid default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_limit integer := least(greatest(coalesce(p_limit,100),1),250);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_search text := nullif(trim(coalesce(p_search,'')), '');
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé aux rapports de gestion.' using errcode = '42501';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'La date de fin doit être égale ou postérieure à la date de début.';
  end if;

  case p_report_key
    when 'fees' then
      with report_rows as (
        select
          c.id,
          s.student_number,
          trim(s.last_name || ' ' || s.first_names) as student_name,
          cl.name as class_name,
          sy.label as school_year,
          fc.name as fee_category,
          c.description,
          coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
          coalesce(c.discount_amount,0)::bigint as discount_amount,
          c.amount_due::bigint as amount_due,
          coalesce(paid.amount_paid,0)::bigint as amount_paid,
          greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint as balance_due,
          c.due_on,
          c.created_at::date as created_on
        from public.student_charges c
        join public.enrollments e on e.id=c.enrollment_id
        join public.students s on s.id=e.student_id
        join public.classes cl on cl.id=e.class_id
        join public.school_years sy on sy.id=e.school_year_id
        join public.fee_categories fc on fc.id=c.fee_category_id
        left join lateral (
          select coalesce(sum(pa.amount),0)::bigint as amount_paid
          from public.payment_allocations pa
          join public.payments p on p.id=pa.payment_id
          where pa.charge_id=c.id and p.status='validated'
            and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC')
        ) paid on true
        where c.status='validated'
          and greatest(c.amount_due-coalesce(paid.amount_paid,0),0)>0
          and (p_school_year_id is null or e.school_year_id=p_school_year_id)
          and (p_from is null or c.created_at::date>=p_from)
          and (p_to is null or c.created_at::date<=p_to)
          and (v_search is null or concat_ws(' ',s.student_number,s.last_name,s.first_names,cl.name,sy.label,fc.name,c.description) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by balance_due desc,student_name,created_on desc limit v_limit offset v_offset
      ) page_rows;

    when 'payments' then
      with report_rows as (
        select p.id,p.receipt_number,p.paid_at,
          s.student_number,trim(s.last_name||' '||s.first_names) as student_name,
          cl.name as class_name,sy.label as school_year,p.amount,
          p.method::text as payment_method,ca.name as account_name,p.payer_name,
          p.external_reference,p.status::text as status,p.cancellation_reason
        from public.payments p
        join public.enrollments e on e.id=p.enrollment_id
        join public.students s on s.id=e.student_id
        join public.classes cl on cl.id=e.class_id
        join public.school_years sy on sy.id=e.school_year_id
        join public.cash_accounts ca on ca.id=p.account_id
        where (p_from is null or p.paid_at >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or p.paid_at < ((p_to+1)::timestamp at time zone 'UTC'))
          and (p_school_year_id is null or e.school_year_id=p_school_year_id)
          and (v_search is null or concat_ws(' ',p.receipt_number,s.student_number,s.last_name,s.first_names,cl.name,sy.label,ca.name,p.payer_name,p.external_reference,p.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by paid_at desc,receipt_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'expenses' then
      with report_rows as (
        select e.id,e.expense_number,e.expense_date,ec.name as category,
          e.beneficiary,e.description,e.amount,ca.name as account_name,
          e.payment_method::text as payment_method,e.external_reference,
          e.status::text as status,e.cancellation_reason
        from public.expenses e
        join public.expense_categories ec on ec.id=e.category_id
        join public.cash_accounts ca on ca.id=e.account_id
        where (p_from is null or e.expense_date>=p_from)
          and (p_to is null or e.expense_date<=p_to)
          and (v_search is null or concat_ws(' ',e.expense_number,ec.name,e.beneficiary,e.description,ca.name,e.external_reference,e.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by expense_date desc,expense_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'cashbook' then
      with report_rows as (
        select t.id,t.transaction_date,ca.name as account_name,t.direction,
          t.transaction_type,t.reference,t.description,t.amount,t.status::text as status,
          t.transfer_group_id
        from public.cash_transactions t
        join public.cash_accounts ca on ca.id=t.account_id
        where (p_from is null or t.transaction_date >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or t.transaction_date < ((p_to+1)::timestamp at time zone 'UTC'))
          and (v_search is null or concat_ws(' ',ca.name,t.reference,t.description,t.transaction_type,t.direction,t.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by transaction_date desc,id limit v_limit offset v_offset
      ) page_rows;

    when 'purchases' then
      with report_rows as (
        select po.id,po.order_number,po.ordered_on,po.expected_delivery_on,
          s.name as supplier,coalesce(pr.request_number,'—') as request_number,
          po.total_amount,po.status::text as status,po.notes
        from public.purchase_orders po
        join public.suppliers s on s.id=po.supplier_id
        left join public.purchase_requests pr on pr.id=po.request_id
        where (p_from is null or po.ordered_on>=p_from)
          and (p_to is null or po.ordered_on<=p_to)
          and (v_search is null or concat_ws(' ',po.order_number,s.name,pr.request_number,po.status::text,po.notes) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by ordered_on desc,order_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'receipts' then
      with report_rows as (
        select gr.id,gr.receipt_number,gr.received_at,po.order_number,
          s.name as supplier,gr.delivery_reference,gr.status,
          (select count(*)::integer from public.goods_receipt_lines grl where grl.goods_receipt_id=gr.id) as line_count,
          gr.notes
        from public.goods_receipts gr
        join public.purchase_orders po on po.id=gr.purchase_order_id
        join public.suppliers s on s.id=po.supplier_id
        where (p_from is null or gr.received_at >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or gr.received_at < ((p_to+1)::timestamp at time zone 'UTC'))
          and (v_search is null or concat_ws(' ',gr.receipt_number,po.order_number,s.name,gr.delivery_reference,gr.status,gr.notes) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by received_at desc,receipt_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'assets' then
      with report_rows as (
        select a.id,a.asset_code,a.name,c.name as category,a.brand,a.model,a.serial_number,
          a.acquired_on,a.acquisition_cost,s.name as supplier,a.location,a.status::text as status,
          a.invoice_reference,a.description
        from public.assets a
        join public.asset_categories c on c.id=a.category_id
        left join public.suppliers s on s.id=a.supplier_id
        where (p_from is null or a.acquired_on>=p_from)
          and (p_to is null or a.acquired_on<=p_to)
          and (v_search is null or concat_ws(' ',a.asset_code,a.name,c.name,a.brand,a.model,a.serial_number,s.name,a.location,a.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by acquired_on desc nulls last,asset_code limit v_limit offset v_offset
      ) page_rows;

    when 'maintenance' then
      with report_rows as (
        select m.id,m.maintenance_date,a.asset_code,a.name as asset_name,m.description,
          s.name as supplier,m.cost,m.status,m.document_path
        from public.asset_maintenance m
        join public.assets a on a.id=m.asset_id
        left join public.suppliers s on s.id=m.supplier_id
        where (p_from is null or m.maintenance_date>=p_from)
          and (p_to is null or m.maintenance_date<=p_to)
          and (v_search is null or concat_ws(' ',a.asset_code,a.name,m.description,s.name,m.status) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by maintenance_date desc,id limit v_limit offset v_offset
      ) page_rows;

    else
      raise exception 'Type de rapport inconnu : %', p_report_key;
  end case;

  return jsonb_build_object('report',p_report_key,'rows',v_rows,'total_count',v_total,'limit',v_limit,'offset',v_offset);
end;
$$;

revoke all on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) from public, anon;
grant execute on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) to authenticated;
comment on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) is
'Rapports paginés calculés côté PostgreSQL pour les frais impayés, encaissements, dépenses, journal de caisse, achats, réceptions, inventaire et maintenance.';

-- Garde la catégorie patrimoniale de la demande jusque dans la ligne de commande.
alter table public.purchase_order_lines add column if not exists category text;

-- Version durcie du RPC de commande : copie explicitement les détails, dont la catégorie.
create or replace function public.create_order_from_request(
  p_request_id uuid,
  p_supplier_id uuid,
  p_order_number text,
  p_ordered_on date default current_date,
  p_expected_delivery_on date default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.purchase_requests%rowtype;
  v_order_id uuid;
  v_total bigint;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation achats/comptabilité requise' using errcode = '42501';
  end if;
  select * into v_request from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.status <> 'approved' then raise exception 'La demande doit être approuvée'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active=true) then
    raise exception 'Fournisseur invalide ou inactif';
  end if;
  if exists(select 1 from public.purchase_orders where request_id=p_request_id and status <> 'cancelled') then
    raise exception 'Un bon de commande existe déjà pour cette demande';
  end if;
  if nullif(trim(coalesce(p_order_number,'')),'') is null then raise exception 'Référence de commande obligatoire'; end if;
  if p_ordered_on is not null and p_ordered_on > current_date then
    raise exception 'La date de commande ne peut pas être dans le futur';
  end if;
  if p_expected_delivery_on is not null and p_ordered_on is not null and p_expected_delivery_on < p_ordered_on then
    raise exception 'La livraison prévue ne peut pas précéder la commande';
  end if;
  select coalesce(sum(round(quantity * estimated_unit_price)),0)::bigint into v_total
  from public.purchase_request_lines where request_id=p_request_id;
  if v_total <= 0 then raise exception 'Le montant de la commande doit être positif'; end if;
  if not exists(select 1 from public.purchase_request_lines where request_id=p_request_id) then
    raise exception 'La demande ne contient aucune ligne';
  end if;
  insert into public.purchase_orders(order_number,request_id,supplier_id,ordered_on,expected_delivery_on,status,total_amount,created_by,notes)
  values(trim(p_order_number),p_request_id,p_supplier_id,coalesce(p_ordered_on,current_date),p_expected_delivery_on,'ordered',v_total,auth.uid(),nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_order_id;
  insert into public.purchase_order_lines(purchase_order_id,description,item_kind,quantity_ordered,unit_price,category)
  select v_order_id,description,item_kind,quantity,estimated_unit_price,nullif(trim(coalesce(category,'')),'')
  from public.purchase_request_lines where request_id=p_request_id;
  update public.purchase_requests set status='ordered' where id=p_request_id;
  return v_order_id;
end;
$$;
revoke all on function public.create_order_from_request(uuid,uuid,text,date,date,text) from public, anon;
grant execute on function public.create_order_from_request(uuid,uuid,text,date,date,text) to authenticated;

-- Les réceptions de lignes d'immobilisations créent automatiquement une fiche d'inventaire
-- par unité entière reçue. Aucun mouvement de trésorerie n'est créé : le règlement reste dans Dépenses.
create or replace function public.receive_purchase_order(
  p_order_id uuid,
  p_receipt_number text,
  p_lines jsonb,
  p_delivery_reference text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.purchase_orders%rowtype;
  v_receipt_id uuid;
  v_receipt_line_id uuid;
  v_line jsonb;
  v_line_id uuid;
  v_qty numeric(12,3);
  v_asset_count integer;
  v_asset_index integer;
  v_asset_offset integer;
  v_asset_category_id uuid;
  v_asset_id uuid;
  v_first_asset_id uuid;
  v_order_line public.purchase_order_lines%rowtype;
  v_all_received boolean;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation réception requise';
  end if;
  if nullif(trim(coalesce(p_receipt_number,'')),'') is null then
    raise exception 'Référence de réception obligatoire';
  end if;
  select * into v_order from public.purchase_orders where id=p_order_id for update;
  if not found then raise exception 'Bon de commande introuvable'; end if;
  if v_order.status not in ('ordered','partially_received') then
    raise exception 'Ce bon de commande ne peut pas être réceptionné';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Ajoutez au moins une ligne reçue';
  end if;

  insert into public.goods_receipts(receipt_number,purchase_order_id,received_by,delivery_reference,notes,status)
  values(trim(p_receipt_number),p_order_id,auth.uid(),nullif(trim(coalesce(p_delivery_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),'draft')
  returning id into v_receipt_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_id := (v_line->>'line_id')::uuid;
    v_qty := (v_line->>'quantity_received')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité reçue invalide'; end if;
    select * into v_order_line
      from public.purchase_order_lines
      where id=v_line_id and purchase_order_id=p_order_id
      for update;
    if not found then raise exception 'Ligne absente de ce bon de commande'; end if;
    if v_order_line.quantity_received + v_qty > v_order_line.quantity_ordered then
      raise exception 'La quantité reçue dépasse la quantité commandée pour %', v_order_line.description;
    end if;

    insert into public.goods_receipt_lines(goods_receipt_id,purchase_order_line_id,quantity_received,condition_note)
    values(v_receipt_id,v_line_id,v_qty,nullif(trim(coalesce(v_line->>'condition_note','')),''))
    returning id into v_receipt_line_id;

    if v_order_line.item_kind='asset' then
      v_asset_category_id := null;
      if v_qty <> trunc(v_qty) then
        raise exception 'La quantité réceptionnée d''une immobilisation doit être un nombre entier.';
      end if;
      v_asset_count := v_qty::integer;
      select count(*)::integer into v_asset_offset from public.assets where purchase_order_line_id=v_line_id;
      if nullif(trim(coalesce(v_order_line.category,'')),'') is not null then
        select id into v_asset_category_id
        from public.asset_categories
        where is_active=true and (lower(code)=lower(trim(v_order_line.category)) or lower(name)=lower(trim(v_order_line.category)))
        limit 1;
        if v_asset_category_id is null then
          raise exception 'Catégorie patrimoniale inconnue ou inactive : %', v_order_line.category;
        end if;
      else
        select id into v_asset_category_id from public.asset_categories where code='AUT' and is_active=true limit 1;
      end if;
      if v_asset_category_id is null then
        raise exception 'La catégorie patrimoniale « Autres biens » doit être active pour appliquer la catégorie par défaut.';
      end if;
      v_first_asset_id := null;
      for v_asset_index in 1..v_asset_count loop
        insert into public.assets(
          asset_code,name,category_id,description,acquired_on,acquisition_cost,
          supplier_id,purchase_order_line_id,location,status,created_by
        ) values (
          'PAT-'||to_char(current_date,'YYYY')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
          case when v_asset_count=1 and v_asset_offset=0 then v_order_line.description else v_order_line.description||' - '||(v_asset_offset+v_asset_index)::text end,
          v_asset_category_id,
          nullif(trim(coalesce(v_line->>'condition_note','')),''),
          current_date,v_order_line.unit_price,v_order.supplier_id,v_line_id,null,'active',auth.uid()
        ) returning id into v_asset_id;
        if v_first_asset_id is null then v_first_asset_id := v_asset_id; end if;
      end loop;
      -- La ligne de réception référence le premier bien créé ; toutes les unités restent liées
      -- à la ligne du bon de commande via assets.purchase_order_line_id.
      update public.goods_receipt_lines set asset_id=v_first_asset_id where id=v_receipt_line_id;
    end if;

    update public.purchase_order_lines set quantity_received=quantity_received+v_qty where id=v_line_id;
  end loop;

  update public.goods_receipts set status='validated' where id=v_receipt_id;
  select bool_and(quantity_received >= quantity_ordered) into v_all_received
  from public.purchase_order_lines where purchase_order_id=p_order_id;
  update public.purchase_orders
  set status=case when v_all_received then 'received'::public.purchase_status else 'partially_received'::public.purchase_status end
  where id=p_order_id;
  return v_receipt_id;
end;
$$;
revoke all on function public.receive_purchase_order(uuid,text,jsonb,text,text) from public, anon;
grant execute on function public.receive_purchase_order(uuid,text,jsonb,text,text) to authenticated;

-- Enregistre une maintenance en une transaction et synchronise le statut du bien.
create or replace function public.register_asset_maintenance(
  p_asset_id uuid,
  p_maintenance_date date,
  p_description text,
  p_supplier_id uuid default null,
  p_cost bigint default 0,
  p_status text default 'planned'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asset public.assets%rowtype;
  v_maintenance_id uuid;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation maintenance requise';
  end if;
  if p_asset_id is null or p_maintenance_date is null or nullif(trim(coalesce(p_description,'')),'') is null then
    raise exception 'Bien, date et description de maintenance obligatoires.';
  end if;
  if coalesce(p_cost,0)<0 then raise exception 'Le coût de maintenance ne peut pas être négatif.'; end if;
  if coalesce(p_status,'planned') not in ('planned','in_progress','completed','cancelled') then
    raise exception 'Statut de maintenance invalide.';
  end if;
  select * into v_asset from public.assets where id=p_asset_id for update;
  if not found then raise exception 'Bien introuvable.'; end if;
  if v_asset.status in ('lost','disposed','retired') then
    raise exception 'Un bien perdu, sorti ou réformé ne peut pas recevoir une nouvelle maintenance.';
  end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and is_active=true) then
    raise exception 'Le prestataire est introuvable ou inactif.';
  end if;

  insert into public.asset_maintenance(asset_id,maintenance_date,description,supplier_id,cost,status,created_by)
  values(p_asset_id,p_maintenance_date,trim(p_description),p_supplier_id,coalesce(p_cost,0),coalesce(p_status,'planned'),auth.uid())
  returning id into v_maintenance_id;

  if p_status='in_progress' and v_asset.status='active' then
    update public.assets set status='under_maintenance',updated_at=now() where id=p_asset_id;
  elsif p_status='completed' and v_asset.status='under_maintenance'
    and not exists(select 1 from public.asset_maintenance m where m.asset_id=p_asset_id and m.status='in_progress' and m.id<>v_maintenance_id) then
    update public.assets set status='active',updated_at=now() where id=p_asset_id;
  end if;
  return v_maintenance_id;
end;
$$;
revoke all on function public.register_asset_maintenance(uuid,date,text,uuid,bigint,text) from public, anon;
grant execute on function public.register_asset_maintenance(uuid,date,text,uuid,bigint,text) to authenticated;

commit;
