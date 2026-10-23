-- Rapprochement bancaire transactionnel et traçable.
begin;
create or replace function public.reconcile_bank_statement_line(p_statement_line_id uuid,p_cash_transaction_id uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_line public.bank_statement_lines%rowtype; v_tx public.cash_transactions%rowtype; v_id uuid; v_uid uuid := auth.uid(); v_amount bigint;
begin
 if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès réservé à l’administration et à la comptabilité'; end if;
 select * into v_line from public.bank_statement_lines where id=p_statement_line_id for update;
 if not found then raise exception 'Ligne de relevé introuvable'; end if;
 select * into v_tx from public.cash_transactions where id=p_cash_transaction_id for update;
 if not found then raise exception 'Mouvement de trésorerie introuvable'; end if;
 if v_tx.status <> 'validated' or v_tx.transaction_type not in ('payment','expense','transfer','adjustment','reversal','opening') then raise exception 'Seuls les mouvements validés peuvent être rapprochés'; end if;
 if v_line.reconciliation_status = 'matched' then raise exception 'Cette ligne est déjà rapprochée'; end if;
 if exists(select 1 from public.bank_reconciliations where statement_line_id=v_line.id and status='matched') then raise exception 'Cette ligne possède déjà un rapprochement validé'; end if;
 if exists(select 1 from public.bank_reconciliations where cash_transaction_id=v_tx.id and status='matched') then raise exception 'Ce mouvement est déjà rapproché'; end if;
 if v_tx.account_id is distinct from (select account_id from public.bank_statement_imports where id=v_line.import_id) then raise exception 'Le compte du mouvement ne correspond pas au compte du relevé'; end if;
 v_amount := case when v_tx.direction='in' then v_line.credit else v_line.debit end;
 if v_amount <= 0 or v_amount <> v_tx.amount then raise exception 'Le montant ou le sens du mouvement ne correspond pas à la ligne du relevé'; end if;
 insert into public.bank_reconciliations(statement_line_id,cash_transaction_id,matched_amount,status,notes,created_by,validated_at,validated_by)
 values(v_line.id,v_tx.id,v_amount,'matched',nullif(trim(p_notes),''),v_uid,now(),v_uid) returning id into v_id;
 update public.bank_statement_lines set reconciliation_status='matched' where id=v_line.id;
 insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
 values(v_uid,'reconcile_bank_statement_line','bank_reconciliations',v_id::text,jsonb_build_object('statement_line_id',v_line.id,'cash_transaction_id',v_tx.id,'amount',v_amount));
 return v_id;
end $$;
revoke all on function public.reconcile_bank_statement_line(uuid,uuid,text) from public,anon;
grant execute on function public.reconcile_bank_statement_line(uuid,uuid,text) to authenticated;
commit;
