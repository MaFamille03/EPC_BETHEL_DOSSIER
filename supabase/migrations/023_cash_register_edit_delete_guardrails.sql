-- EPC BETHEL 1.18.0 — verrouille la modification/suppression dans le registre unique de caisse.
begin;

create or replace function public.update_manual_cash_movement(
  p_transaction_id uuid,p_direction text,p_amount bigint,p_transaction_date date,p_payment_channel text,p_reference text,p_description text,p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid(); v_at timestamptz; v_available bigint; v_main_cash_id uuid; v_old_channel_balance bigint;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Modification réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  select a.id into v_main_cash_id from public.cash_accounts a where a.is_active and a.kind::text='cash' order by (a.code='CAISSE') desc,a.created_at,a.id limit 1;
  if v_main_cash_id is null or v_tx.account_id<>v_main_cash_id then raise exception 'Cette ligne ne fait pas partie du registre unique de caisse principal.'; end if;
  if v_tx.transaction_type<>'adjustment' or v_tx.payment_id is not null or v_tx.expense_id is not null or v_tx.transfer_group_id is not null or v_tx.reverses_transaction_id is not null then
    raise exception 'Seules les lignes de caisse saisies manuellement peuvent être modifiées ici. Les reçus et dépenses doivent être corrigés dans leur module.';
  end if;
  if exists(select 1 from public.bank_reconciliations r where r.cash_transaction_id=v_tx.id and r.status='matched') then raise exception 'Ce mouvement est rapproché et ne peut plus être modifié.'; end if;
  if coalesce(p_direction,'') not in ('in','out') or p_amount is null or p_amount<=0 or p_transaction_date is null or p_transaction_date>current_date
    or coalesce(p_payment_channel,'') not in ('especes','orange_money','wave','moov_money') or coalesce(trim(p_description),'')='' or coalesce(trim(p_reason),'')='' then
    raise exception 'Vérifiez le sens, le montant, la date, le moyen de paiement, le libellé et le motif de modification.';
  end if;
  v_at := ((p_transaction_date+1)::timestamp at time zone 'UTC')-interval '1 microsecond';
  v_old_channel_balance := public.cash_method_balance(v_tx.payment_channel,now(),v_tx.id);
  if v_old_channel_balance<0 then raise exception 'Modification refusée : les mouvements postérieurs entraîneraient un solde négatif pour le moyen de paiement d’origine.'; end if;
  v_available := public.cash_method_balance(p_payment_channel,v_at,v_tx.id);
  if p_direction='out' and v_available<p_amount then raise exception 'Solde insuffisant pour ce moyen de paiement. Disponible : %, demandé : %',v_available,p_amount; end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'update_manual_cash_movement','cash_transactions',v_tx.id::text,jsonb_build_object('reason',trim(p_reason),'before',jsonb_build_object('date',v_tx.transaction_date,'direction',v_tx.direction,'amount',v_tx.amount,'channel',v_tx.payment_channel,'reference',v_tx.reference,'description',v_tx.description),'after',jsonb_build_object('date',p_transaction_date,'direction',p_direction,'amount',p_amount,'channel',p_payment_channel,'reference',p_reference,'description',p_description)));
  update public.cash_transactions set transaction_date=(p_transaction_date::timestamp at time zone 'UTC')+interval '12 hours',direction=p_direction,amount=p_amount,payment_channel=p_payment_channel,reference=nullif(trim(coalesce(p_reference,'')),''),description=trim(p_description)
  where id=v_tx.id;
  if public.cash_method_balance(v_tx.payment_channel,now(),null)<0 then raise exception 'Modification refusée : le solde du moyen de paiement d’origine deviendrait négatif.'; end if;
  if public.cash_method_balance(p_payment_channel,now(),null)<0 then raise exception 'Modification refusée : le solde du moyen de paiement choisi deviendrait négatif.'; end if;
end $$;
revoke all on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) from public,anon;
grant execute on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) to authenticated;

create or replace function public.delete_manual_cash_movement(p_transaction_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid(); v_main_cash_id uuid;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Suppression réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  select a.id into v_main_cash_id from public.cash_accounts a where a.is_active and a.kind::text='cash' order by (a.code='CAISSE') desc,a.created_at,a.id limit 1;
  if v_main_cash_id is null or v_tx.account_id<>v_main_cash_id then raise exception 'Cette ligne ne fait pas partie du registre unique de caisse principal.'; end if;
  if v_tx.transaction_type<>'adjustment' or v_tx.payment_id is not null or v_tx.expense_id is not null or v_tx.transfer_group_id is not null or v_tx.reverses_transaction_id is not null then
    raise exception 'Seules les lignes de caisse saisies manuellement peuvent être supprimées ici. Les reçus et dépenses doivent être annulés dans leur module.';
  end if;
  if exists(select 1 from public.bank_reconciliations r where r.cash_transaction_id=v_tx.id and r.status='matched') then raise exception 'Ce mouvement est rapproché et ne peut plus être supprimé.'; end if;
  if exists(select 1 from public.cash_transactions t where t.reverses_transaction_id=v_tx.id) then raise exception 'Une contrepassation existe pour ce mouvement.'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Le motif de suppression est obligatoire.'; end if;
  if public.cash_method_balance(v_tx.payment_channel,now(),v_tx.id)<0 then
    raise exception 'Suppression refusée : les mouvements postérieurs entraîneraient un solde négatif pour ce moyen de paiement.';
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'delete_manual_cash_movement','cash_transactions',v_tx.id::text,jsonb_build_object('reason',trim(p_reason),'deleted_transaction',to_jsonb(v_tx)));
  delete from public.cash_transactions where id=v_tx.id;
end $$;
revoke all on function public.delete_manual_cash_movement(uuid,text) from public,anon;
grant execute on function public.delete_manual_cash_movement(uuid,text) to authenticated;

commit;
