-- EPC BETHEL — Migration 008 : workflows Achats & Patrimoine
-- Sécurité : les fonctions SECURITY DEFINER utilisent un search_path vide et des références de schéma qualifiées.
-- À exécuter après les migrations 001 à 007, uniquement en environnement de test avant production.

-- Catégories de biens initiales, idempotentes.
insert into public.asset_categories(code, name, useful_life_months)
values
 ('INFO','Matériel informatique',48),
 ('MOB','Mobilier scolaire et de bureau',120),
 ('PED','Matériel pédagogique',60),
 ('ELEC','Équipements électriques',60),
 ('IMM','Installations et aménagements',120),
 ('AUT','Autres biens',60)
on conflict (code) do nothing;

-- RLS de décision des demandes : le demandeur ne peut pas décider sa propre demande.
create policy purchase_requests_submit_own_draft
on public.purchase_requests for update to authenticated
using (status = 'draft' and requested_by = (select auth.uid()))
with check (requested_by = (select auth.uid()) and status in ('draft','submitted'));

create policy purchase_requests_decision
on public.purchase_requests for update to authenticated
using (status = 'submitted' and public.has_any_role(array['admin','direction']::public.app_role[]))
with check (status in ('approved','rejected') and public.has_any_role(array['admin','direction']::public.app_role[]));

-- Soumission atomique d'une demande : vérifie la présence d'au moins une ligne.
create or replace function public.submit_purchase_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_request public.purchase_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  select * into v_request from public.purchase_requests where id = p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.requested_by <> auth.uid() and not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Vous ne pouvez pas soumettre cette demande';
  end if;
  if v_request.status <> 'draft' then raise exception 'Seule une demande en brouillon peut être soumise'; end if;
  if not exists(select 1 from public.purchase_request_lines where request_id = p_request_id) then
    raise exception 'Ajoutez au moins une ligne avant la soumission';
  end if;
  update public.purchase_requests set status='submitted', submitted_at=now()
  where id=p_request_id;
end;
$$;

-- Décision de la direction/admin avec note obligatoire en cas de refus.
create or replace function public.decide_purchase_request(
  p_request_id uuid, p_approve boolean, p_decision_note text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_status public.purchase_status;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Autorisation direction ou administrateur requise';
  end if;
  select status into v_status from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_status <> 'submitted' then raise exception 'La demande doit être soumise avant décision'; end if;
  if not p_approve and nullif(trim(coalesce(p_decision_note,'')),'') is null then
    raise exception 'Le motif du refus est obligatoire';
  end if;
  update public.purchase_requests
  set status = case when p_approve then 'approved'::public.purchase_status else 'rejected'::public.purchase_status end,
      approved_by = case when p_approve then auth.uid() else null end,
      approved_at = case when p_approve then now() else null end,
      decision_note = nullif(trim(coalesce(p_decision_note,'')),'')
  where id=p_request_id;
end;
$$;

-- Crée un bon de commande à partir d'une demande approuvée et copie ses lignes.
-- Aucun mouvement de trésorerie n'est créé ici : le règlement doit passer par Dépenses.
create or replace function public.create_order_from_request(
  p_request_id uuid, p_supplier_id uuid, p_order_number text,
  p_ordered_on date default current_date, p_expected_delivery_on date default null, p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_request public.purchase_requests%rowtype; v_order_id uuid; v_total bigint;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation achats/comptabilité requise';
  end if;
  select * into v_request from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.status <> 'approved' then raise exception 'La demande doit être approuvée'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active) then raise exception 'Fournisseur invalide ou inactif'; end if;
  if exists(select 1 from public.purchase_orders where request_id=p_request_id and status <> 'cancelled') then
    raise exception 'Un bon de commande existe déjà pour cette demande';
  end if;
  if nullif(trim(coalesce(p_order_number,'')),'') is null then raise exception 'Référence de commande obligatoire'; end if;
  select coalesce(sum(round(quantity * estimated_unit_price)),0)::bigint into v_total
  from public.purchase_request_lines where request_id=p_request_id;
  if v_total <= 0 then raise exception 'Le montant de la commande doit être positif'; end if;
  insert into public.purchase_orders(order_number,request_id,supplier_id,ordered_on,expected_delivery_on,status,total_amount,created_by,notes)
  values(trim(p_order_number),p_request_id,p_supplier_id,coalesce(p_ordered_on,current_date),p_expected_delivery_on,'ordered',v_total,auth.uid(),p_notes)
  returning id into v_order_id;
  insert into public.purchase_order_lines(purchase_order_id,description,item_kind,quantity_ordered,unit_price)
  select v_order_id,description,item_kind,quantity,estimated_unit_price
  from public.purchase_request_lines where request_id=p_request_id;
  update public.purchase_requests set status='ordered' where id=p_request_id;
  return v_order_id;
end;
$$;

revoke all on function public.submit_purchase_request(uuid) from public;
revoke all on function public.decide_purchase_request(uuid,boolean,text) from public;
revoke all on function public.create_order_from_request(uuid,uuid,text,date,date,text) from public;
grant execute on function public.submit_purchase_request(uuid) to authenticated;
grant execute on function public.decide_purchase_request(uuid,boolean,text) to authenticated;
grant execute on function public.create_order_from_request(uuid,uuid,text,date,date,text) to authenticated;

comment on function public.create_order_from_request(uuid,uuid,text,date,date,text) is
'Crée un bon de commande et ses lignes à partir d’une demande approuvée. Ne génère aucun mouvement de trésorerie.';

-- Réception partielle ou complète des lignes d'un bon de commande.
create or replace function public.receive_purchase_order(
  p_order_id uuid, p_receipt_number text, p_lines jsonb, p_delivery_reference text default null, p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_order public.purchase_orders%rowtype; v_receipt_id uuid; v_line jsonb; v_line_id uuid; v_qty numeric(12,3); v_order_line public.purchase_order_lines%rowtype; v_all_received boolean;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation réception requise';
  end if;
  select * into v_order from public.purchase_orders where id=p_order_id for update;
  if not found then raise exception 'Bon de commande introuvable'; end if;
  if v_order.status not in ('ordered','partially_received') then raise exception 'Ce bon de commande ne peut pas être réceptionné'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Ajoutez au moins une ligne reçue'; end if;
  insert into public.goods_receipts(receipt_number,purchase_order_id,received_by,delivery_reference,notes,status)
  values(trim(p_receipt_number),p_order_id,auth.uid(),p_delivery_reference,p_notes,'draft') returning id into v_receipt_id;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_id := (v_line->>'line_id')::uuid;
    v_qty := (v_line->>'quantity_received')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité reçue invalide'; end if;
    select * into v_order_line from public.purchase_order_lines where id=v_line_id and purchase_order_id=p_order_id for update;
    if not found then raise exception 'Ligne absente de ce bon de commande'; end if;
    if v_order_line.quantity_received + v_qty > v_order_line.quantity_ordered then raise exception 'La quantité reçue dépasse la quantité commandée pour %', v_order_line.description; end if;
    insert into public.goods_receipt_lines(goods_receipt_id,purchase_order_line_id,quantity_received,condition_note)
    values(v_receipt_id,v_line_id,v_qty,nullif(v_line->>'condition_note',''));
    update public.purchase_order_lines set quantity_received=quantity_received+v_qty where id=v_line_id;
  end loop;
  update public.goods_receipts set status='validated' where id=v_receipt_id;
  select bool_and(quantity_received >= quantity_ordered) into v_all_received from public.purchase_order_lines where purchase_order_id=p_order_id;
  update public.purchase_orders set status=case when v_all_received then 'received'::public.purchase_status else 'partially_received'::public.purchase_status end where id=p_order_id;
  return v_receipt_id;
end;
$$;
revoke all on function public.receive_purchase_order(uuid,text,jsonb,text,text) from public;
grant execute on function public.receive_purchase_order(uuid,text,jsonb,text,text) to authenticated;

-- Transfert atomique : journal de mouvement et mise à jour de l'emplacement dans une transaction.
create or replace function public.transfer_asset_location(
  p_asset_id uuid, p_to_location text, p_reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_asset public.assets%rowtype;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Autorisation patrimoine requise';
  end if;
  if nullif(trim(coalesce(p_to_location,'')),'') is null or nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Destination et motif obligatoires';
  end if;
  select * into v_asset from public.assets where id=p_asset_id for update;
  if not found then raise exception 'Bien introuvable'; end if;
  if v_asset.status in ('disposed','retired','lost') then raise exception 'Ce bien ne peut pas être transféré'; end if;
  insert into public.asset_movements(asset_id,movement_kind,from_location,to_location,reason,created_by)
  values(p_asset_id,'transfer',v_asset.location,trim(p_to_location),trim(p_reason),auth.uid());
  update public.assets set location=trim(p_to_location),updated_at=now() where id=p_asset_id;
end;
$$;
revoke all on function public.transfer_asset_location(uuid,text,text) from public;
grant execute on function public.transfer_asset_location(uuid,text,text) to authenticated;

-- Permet à l'auteur de retirer un brouillon incomplet créé avant un échec de ligne.
create policy purchase_requests_delete_own_draft
on public.purchase_requests for delete to authenticated
using (status='draft' and requested_by=(select auth.uid()));
