-- EPC BETHEL — Étape 3 : trésorerie, dépenses et transferts
-- À exécuter après les migrations 001 à 006 dans un projet Supabase de développement.

create table if not exists public.expense_sequences (
  sequence_year integer primary key,
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default now()
);

insert into public.expense_categories(code,name,is_active) values
 ('FOURNITURES','Fournitures scolaires et de bureau',true),
 ('SALAIRES','Salaires et rémunérations',true),
 ('EAU_ELECTRICITE','Eau et électricité',true),
 ('ENTRETIEN','Entretien et réparations',true),
 ('TRANSPORT','Transport et déplacements',true),
 ('ACHATS','Achats et équipements',true),
 ('AUTRES','Autres dépenses',true)
on conflict (code) do nothing;

create or replace function public.current_account_balance(p_account_id uuid, p_at timestamptz default now())
returns bigint
language sql stable security invoker
set search_path = ''
as $$
  select coalesce(a.opening_balance,0)::bigint
    + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0)::bigint
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id=a.id and t.status='validated' and t.transaction_date <= p_at
  where a.id=p_account_id
  group by a.id,a.opening_balance
$$;

create or replace function public.get_treasury_balances()
returns table(account_id uuid,account_code text,account_name text,account_kind public.account_kind,opening_balance bigint,balance bigint,total_in bigint,total_out bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  return query
  select a.id,a.code,a.name,a.kind,a.opening_balance,
    (coalesce(a.opening_balance,0)+coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0))::bigint as balance,
    coalesce(sum(t.amount) filter(where t.direction='in'),0)::bigint as total_in,
    coalesce(sum(t.amount) filter(where t.direction='out'),0)::bigint as total_out
  from public.cash_accounts a left join public.cash_transactions t on t.account_id=a.id and t.status='validated'
  where a.is_active=true group by a.id,a.code,a.name,a.kind,a.opening_balance order by a.name;
end $$;

create or replace function public.create_expense(
  p_expense_date date,
  p_category_id uuid,
  p_beneficiary text,
  p_description text,
  p_amount bigint,
  p_account_id uuid,
  p_payment_method public.payment_method,
  p_external_reference text default null,
  p_document_path text default null
)
returns public.expenses
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_year integer := extract(year from coalesce(p_expense_date,current_date))::integer;
  v_next bigint;
  v_expense public.expenses%rowtype;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Création de dépense réservée à la comptabilité ou à l’administration';
  end if;
  if p_expense_date is null or p_category_id is null or p_account_id is null then raise exception 'Date, catégorie et compte obligatoires'; end if;
  if coalesce(trim(p_beneficiary),'')='' or coalesce(trim(p_description),'')='' then raise exception 'Bénéficiaire et désignation obligatoires'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être un entier positif en FCFA'; end if;
  if not exists(select 1 from public.expense_categories where id=p_category_id and is_active) then raise exception 'Catégorie inactive ou introuvable'; end if;
  if not exists(select 1 from public.cash_accounts where id=p_account_id and is_active) then raise exception 'Compte inactif ou introuvable'; end if;

  insert into public.expense_sequences(sequence_year,last_value) values(v_year,0) on conflict(sequence_year) do nothing;
  update public.expense_sequences set last_value=last_value+1,updated_at=now() where sequence_year=v_year returning last_value into v_next;

  insert into public.expenses(expense_number,expense_date,category_id,beneficiary,description,amount,account_id,payment_method,external_reference,document_path,status,created_by)
  values('DEP-'||v_year::text||'-'||lpad(v_next::text,6,'0'),p_expense_date,p_category_id,trim(p_beneficiary),trim(p_description),p_amount,p_account_id,p_payment_method,nullif(trim(p_external_reference),''),p_document_path,'draft',v_uid)
  returning * into v_expense;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'create_expense','expenses',v_expense.id::text,jsonb_build_object('expense_number',v_expense.expense_number,'amount',v_expense.amount,'status','draft'));
  return v_expense;
end $$;

-- Remplace la validation de dépense pour contrôler le solde disponible et l'idempotence.
create or replace function public.validate_expense(p_expense_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_balance bigint;
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'draft' then raise exception 'Seule une dépense en brouillon peut être validée'; end if;
  perform 1 from public.cash_accounts where id=v_expense.account_id and is_active=true for update;
  if not found then raise exception 'Compte inactif ou introuvable'; end if;
  if exists(select 1 from public.cash_transactions where expense_id=v_expense.id and transaction_type='expense') then raise exception 'Un mouvement existe déjà pour cette dépense'; end if;
  v_balance := public.current_account_balance(v_expense.account_id, (v_expense.expense_date::timestamp at time zone 'UTC') + interval '1 day' - interval '1 microsecond');
  if v_balance < v_expense.amount then raise exception 'Solde insuffisant à la date de la dépense : disponible %, demandé %',v_balance,v_expense.amount; end if;

  update public.expenses set status='validated',validated_at=now(),validated_by=v_uid where id=p_expense_id;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,expense_id,reference,description,status,created_by,validated_at,validated_by)
  values(v_expense.account_id,(v_expense.expense_date::timestamp at time zone 'UTC'),'out',v_expense.amount,'expense',v_expense.id,v_expense.expense_number,v_expense.description,'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'validate_expense','expenses',p_expense_id::text,jsonb_build_object('amount',v_expense.amount,'expense_number',v_expense.expense_number,'account_id',v_expense.account_id));
end $$;

create or replace function public.cancel_expense(p_expense_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_tx public.cash_transactions%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then raise exception 'Annulation réservée à la direction ou à l’administration'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Le motif d’annulation est obligatoire'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'validated' then raise exception 'Seule une dépense validée peut être annulée'; end if;
  select * into v_tx from public.cash_transactions where expense_id=v_expense.id and transaction_type='expense' and status='validated' for update;
  if not found then raise exception 'Mouvement d’origine introuvable'; end if;
  if exists(select 1 from public.cash_transactions where reverses_transaction_id=v_tx.id and status='validated') then raise exception 'Cette dépense a déjà été contrepassée'; end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,reverses_transaction_id,reference,description,status,created_by,validated_at,validated_by)
  values(v_tx.account_id,now(),'in',v_tx.amount,'reversal',v_tx.id,v_expense.expense_number,'Annulation dépense '||v_expense.expense_number||' : '||trim(p_reason),'validated',v_uid,now(),v_uid);
  update public.expenses set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason) where id=v_expense.id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'cancel_expense','expenses',v_expense.id::text,jsonb_build_object('reason',trim(p_reason),'amount',v_expense.amount,'expense_number',v_expense.expense_number));
end $$;

-- Empêche une sortie supérieure au solde au moment du transfert.
create or replace function public.transfer_between_accounts(
  p_source_account_id uuid,p_destination_account_id uuid,p_amount bigint,p_transfer_date timestamptz,p_reference text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_group uuid := gen_random_uuid(); v_uid uuid := (select auth.uid()); v_balance bigint; v_when timestamptz := coalesce(p_transfer_date,now());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  if p_source_account_id=p_destination_account_id then raise exception 'Les comptes source et destination doivent être différents'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Montant invalide'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Libellé obligatoire'; end if;
  perform 1 from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true order by id for update;
  if (select count(*) from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true)<>2 then raise exception 'Un compte est inactif ou introuvable'; end if;
  v_balance := public.current_account_balance(p_source_account_id,v_when);
  if v_balance<p_amount then raise exception 'Solde insuffisant pour le transfert : disponible %, demandé %',v_balance,p_amount; end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,created_by,validated_at,validated_by)
  values(p_source_account_id,v_when,'out',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert sortant : '||trim(p_description),'validated',v_uid,now(),v_uid),
        (p_destination_account_id,v_when,'in',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert entrant : '||trim(p_description),'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details) values(v_uid,'transfer_between_accounts','cash_transactions',v_group::text,jsonb_build_object('source_account_id',p_source_account_id,'destination_account_id',p_destination_account_id,'amount',p_amount,'reference',p_reference));
  return v_group;
end $$;

revoke all on function public.current_account_balance(uuid,timestamptz) from public,anon;
revoke all on function public.get_treasury_balances() from public,anon;
revoke all on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) from public,anon;
revoke all on function public.validate_expense(uuid) from public,anon;
revoke all on function public.cancel_expense(uuid,text) from public,anon;
revoke all on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) from public,anon;
grant execute on function public.current_account_balance(uuid,timestamptz) to authenticated;
grant execute on function public.get_treasury_balances() to authenticated;
grant execute on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) to authenticated;
grant execute on function public.validate_expense(uuid) to authenticated;
grant execute on function public.cancel_expense(uuid,text) to authenticated;
grant execute on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) to authenticated;
