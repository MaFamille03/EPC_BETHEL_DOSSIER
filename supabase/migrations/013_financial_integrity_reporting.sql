-- EPC BETHEL — Étape 4 : intégrité financière et agrégats calculés côté base.
-- À exécuter après les migrations 001 à 012 sur un projet de développement,
-- puis à valider avec des comptes de test avant toute utilisation en production.

begin;

-- Le solde tient compte de la date d'ouverture du compte : un solde initial futur
-- ne doit pas être considéré comme disponible avant sa date d'effet.
create or replace function public.current_account_balance(
  p_account_id uuid,
  p_at timestamptz default now()
)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select
    case
      when a.opening_date <= (p_at at time zone 'UTC')::date then coalesce(a.opening_balance,0)::bigint
      else 0::bigint
    end
    + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0)::bigint
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id=a.id
   and t.status='validated'
   and t.transaction_date <= p_at
  where a.id=p_account_id
  group by a.id,a.opening_balance,a.opening_date
$$;

revoke all on function public.current_account_balance(uuid,timestamptz) from public, anon;
grant execute on function public.current_account_balance(uuid,timestamptz) to authenticated;

-- Un solde courant ne doit pas inclure d'opérations datées dans le futur.
-- Les mouvements historiques validés restent pris en compte pour préserver l'historique.
create or replace function public.get_treasury_balances()
returns table(
  account_id uuid,
  account_code text,
  account_name text,
  account_kind public.account_kind,
  opening_balance bigint,
  balance bigint,
  total_in bigint,
  total_out bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation de la trésorerie.' using errcode = '42501';
  end if;

  return query
  select
    a.id,
    a.code,
    a.name,
    a.kind,
    a.opening_balance,
    (case when a.opening_date <= current_date then coalesce(a.opening_balance,0) else 0 end
      + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end)
          filter (where t.id is not null),0))::bigint as balance,
    coalesce(sum(t.amount) filter(where t.direction='in'),0)::bigint as total_in,
    coalesce(sum(t.amount) filter(where t.direction='out'),0)::bigint as total_out
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id = a.id
   and t.status = 'validated'
   and t.transaction_date < ((current_date + 1)::timestamp at time zone 'UTC')
  where a.is_active = true
  group by a.id,a.code,a.name,a.kind,a.opening_balance,a.opening_date
  order by a.name;
end;
$$;

revoke all on function public.get_treasury_balances() from public, anon;
grant execute on function public.get_treasury_balances() to authenticated;


-- Encaissements, validations de dépenses et transferts : les opérations datées dans le futur
-- sont refusées côté base, même si un client contourne les contrôles d'interface.
create or replace function public.register_student_payment(
  p_enrollment_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_receipt text;
  v_payment_id uuid;
  v_remaining bigint;
  v_total_due bigint;
  v_open bigint;
  v_charge record;
  v_installment record;
  v_take bigint;
  v_account public.cash_accounts%rowtype;
begin
  if v_user is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Seul un administrateur ou la comptabilité peut enregistrer un encaissement';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être strictement positif'; end if;
  if p_enrollment_id is null then raise exception 'Sélectionnez une inscription'; end if;
  if p_paid_at is null then raise exception 'La date du paiement est obligatoire'; end if;
  if (p_paid_at at time zone 'UTC')::date > current_date then raise exception 'La date du paiement ne peut pas être dans le futur.'; end if;

  perform 1 from public.enrollments e
   where e.id = p_enrollment_id and e.status in ('inscrit','reinscrit')
   for update;
  if not found then raise exception 'Inscription active introuvable'; end if;

  select * into v_account from public.cash_accounts
   where id = p_account_id and is_active = true for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;

  -- Calcule le reste à payer sur les frais validés. Les échéances sont traitées en premier,
  -- par date puis numéro; les frais ponctuels sans échéances viennent ensuite.
  select coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint
    into v_total_due
    from public.student_charges c
    left join lateral (
      select sum(pa.amount)::bigint as amount_paid
        from public.payment_allocations pa
        join public.payments p on p.id = pa.payment_id and p.status = 'validated'
         and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
       where pa.charge_id = c.id
    ) paid on true
   where c.enrollment_id = p_enrollment_id and c.status = 'validated';

  if p_amount > v_total_due then
    raise exception 'Le versement (%) dépasse le solde total dû (%)', p_amount, v_total_due;
  end if;
  if v_total_due <= 0 then raise exception 'Aucun frais impayé pour cette inscription'; end if;

  v_receipt := public.allocate_receipt_number(p_paid_at);
  insert into public.payments(
    receipt_number,enrollment_id,paid_at,amount,method,account_id,external_reference,
    payer_name,notes,status,created_by
  ) values (
    v_receipt,p_enrollment_id,p_paid_at,p_amount,p_method,p_account_id,
    nullif(trim(p_external_reference),''),nullif(trim(p_payer_name),''),
    nullif(trim(p_notes),''),'draft',v_user
  ) returning id into v_payment_id;

  v_remaining := p_amount;

  -- 1) Echéances de scolarité, avec vérification du montant restant de chacune.
  for v_installment in
    select i.id as installment_id, i.charge_id, i.amount_due, i.due_on, i.installment_no
      from public.installments i
      join public.student_charges c on c.id = i.charge_id
     where c.enrollment_id = p_enrollment_id and c.status = 'validated'
     order by i.due_on, i.installment_no, i.id
  loop
    exit when v_remaining = 0;
    -- Seuls les paiements validés réduisent le solde de l'échéance.
    v_open := greatest(v_installment.amount_due - coalesce((
      select sum(pa.amount)::bigint from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.installment_id=v_installment.installment_id
    ),0),0);
    if v_open > 0 then
      v_take := least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_installment.charge_id,v_installment.installment_id,v_take,v_user);
      v_remaining := v_remaining-v_take;
    end if;
  end loop;

  -- 2) Frais ponctuels qui n'ont pas d'échéances.
  for v_charge in
    select c.id,c.amount_due
      from public.student_charges c
     where c.enrollment_id=p_enrollment_id and c.status='validated'
       and not exists(select 1 from public.installments i where i.charge_id=c.id)
     order by c.due_on nulls last,c.created_at,c.id
  loop
    exit when v_remaining=0;
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where p.status='validated' and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')),0),0)::bigint
      into v_open
      from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
     where pa.charge_id=v_charge.id;
    if v_open>0 then
      v_take:=least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_charge.id,null,v_take,v_user);
      v_remaining:=v_remaining-v_take;
    end if;
  end loop;

  if v_remaining<>0 then raise exception 'Affectation automatique incomplète; opération annulée'; end if;
  perform public.validate_payment(v_payment_id);
  return jsonb_build_object('id',v_payment_id,'receipt_number',v_receipt,'amount',p_amount,'status','validated');
end;
$$;
revoke all on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) from public, anon;
grant execute on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) to authenticated;

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
  if p_expense_date > current_date then raise exception 'La date d’une dépense ne peut pas être dans le futur.'; end if;
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
revoke all on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) from public, anon;
grant execute on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) to authenticated;

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
  if v_expense.expense_date > current_date then raise exception 'Une dépense datée dans le futur ne peut pas être validée.'; end if;
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
revoke all on function public.validate_expense(uuid) from public, anon;
grant execute on function public.validate_expense(uuid) to authenticated;

create or replace function public.transfer_between_accounts(
  p_source_account_id uuid,p_destination_account_id uuid,p_amount bigint,p_transfer_date timestamptz,p_reference text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_group uuid := gen_random_uuid(); v_uid uuid := (select auth.uid()); v_balance bigint; v_when timestamptz := coalesce(p_transfer_date,now());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  if p_source_account_id=p_destination_account_id then raise exception 'Les comptes source et destination doivent être différents'; end if;
  if (v_when at time zone 'UTC')::date > current_date then raise exception 'La date du transfert ne peut pas être dans le futur.'; end if;
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
revoke all on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) from public, anon;
grant execute on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) to authenticated;

-- Liste financière des frais : les montants payés sont agrégés dans PostgreSQL
-- sur l'ensemble des paiements validés, et non à partir d'un sous-ensemble chargé dans le navigateur.
create or replace function public.get_school_fee_ledger(
  p_school_year_id uuid default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_query text default null
)
returns table(
  charge_id uuid,
  enrollment_id uuid,
  student_name text,
  student_number text,
  class_name text,
  school_year text,
  category_name text,
  description text,
  gross_amount bigint,
  discount_amount bigint,
  amount_due bigint,
  amount_paid bigint,
  balance_due bigint,
  charge_status text,
  due_on date,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des frais scolaires.' using errcode = '42501';
  end if;
  if p_offset is null or p_offset < 0 then raise exception 'Le décalage de pagination est invalide.'; end if;

  return query
  with charge_rows as (
    select
      c.id as charge_id,
      c.enrollment_id,
      trim(s.last_name || ' ' || s.first_names) as student_name,
      s.student_number,
      cl.name as class_name,
      sy.label as school_year,
      fc.name as category_name,
      c.description,
      coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
      coalesce(c.discount_amount,0)::bigint as discount_amount,
      c.amount_due::bigint as amount_due,
      coalesce(paid.amount_paid,0)::bigint as amount_paid,
      greatest(c.amount_due - coalesce(paid.amount_paid,0),0)::bigint as balance_due,
      c.status::text as charge_status,
      c.due_on,
      c.created_at
    from public.student_charges c
    join public.enrollments e on e.id = c.enrollment_id
    join public.students s on s.id = e.student_id
    join public.classes cl on cl.id = e.class_id
    join public.school_years sy on sy.id = e.school_year_id
    join public.fee_categories fc on fc.id = c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id and p.status = 'validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id = c.id
    ) paid on true
    where c.status = 'validated'
      and (p_school_year_id is null or e.school_year_id = p_school_year_id)
      and (nullif(trim(p_query),'') is null or concat_ws(' ',s.last_name,s.first_names,s.student_number,cl.name,sy.label,fc.name,c.description) ilike '%' || trim(p_query) || '%')
  ), counted as (
    select charge_rows.*, count(*) over()::bigint as total_count from charge_rows
  )
  select
    counted.charge_id,counted.enrollment_id,counted.student_name,counted.student_number,
    counted.class_name,counted.school_year,counted.category_name,counted.description,
    counted.gross_amount,counted.discount_amount,counted.amount_due,counted.amount_paid,
    counted.balance_due,counted.charge_status,counted.due_on,counted.created_at,counted.total_count
  from counted
  order by counted.created_at desc, counted.charge_id
  limit least(greatest(coalesce(p_limit,100),1),100)
  offset p_offset;
end;
$$;

revoke all on function public.get_school_fee_ledger(uuid,integer,integer,text) from public, anon;
grant execute on function public.get_school_fee_ledger(uuid,integer,integer,text) to authenticated;

-- Liste des inscriptions qui ont un solde positif, utilisée pour éviter de charger
-- tous les frais et affectations imbriqués dans l'interface des encaissements.
create or replace function public.get_enrollment_payment_options()
returns table(
  enrollment_id uuid,
  option_label text,
  balance_due bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des soldes élèves.' using errcode = '42501';
  end if;

  return query
  select
    e.id,
    trim(s.last_name || ' ' || s.first_names) || ' · ' || coalesce(s.student_number,'Sans matricule') || ' · ' || cl.name || ' · ' || sy.label ||
      ' · Solde ' || to_char(balance.balance_due::numeric, 'FM999G999G999G999G990') || ' FCFA',
    balance.balance_due
  from public.enrollments e
  join public.students s on s.id=e.student_id
  join public.classes cl on cl.id=e.class_id
  join public.school_years sy on sy.id=e.school_year_id
  join lateral (
    select coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint as balance_due
    from public.student_charges c
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id=c.id
    ) paid on true
    where c.enrollment_id=e.id and c.status='validated'
  ) balance on true
  where e.status in ('inscrit','reinscrit')
    and s.status='actif'
    and balance.balance_due > 0
  order by s.last_name,s.first_names,sy.starts_on desc;
end;
$$;

revoke all on function public.get_enrollment_payment_options() from public, anon;
grant execute on function public.get_enrollment_payment_options() to authenticated;

-- Résumé financier exact calculé côté base. Les montants affichés sur le tableau
-- de bord ne dépendent plus des limites d'API ou du nombre de lignes téléchargées.
create or replace function public.get_financial_summary(
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_receipts_total bigint := 0;
  v_receipts_period bigint := 0;
  v_receipts_today bigint := 0;
  v_receipt_count bigint := 0;
  v_expenses_total bigint := 0;
  v_expenses_period bigint := 0;
  v_expense_count bigint := 0;
  v_fee_gross bigint := 0;
  v_discount bigint := 0;
  v_fee_net bigint := 0;
  v_paid_allocated bigint := 0;
  v_balance_due bigint := 0;
  v_treasury bigint := 0;
  v_open_drafts bigint := 0;
  v_open_drafts_amount bigint := 0;
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé aux indicateurs financiers.' using errcode = '42501';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'La date de fin doit être égale ou postérieure à la date de début.';
  end if;

  select coalesce(sum(p.amount),0)::bigint, count(*)::bigint,
         coalesce(sum(p.amount) filter (
           where (p_from is null or p.paid_at >= p_from::timestamp at time zone 'UTC')
             and (p_to is null or p.paid_at < (p_to + 1)::timestamp at time zone 'UTC')
         ),0)::bigint,
         coalesce(sum(p.amount) filter (where p.paid_at >= current_date::timestamp at time zone 'UTC'
                                          and p.paid_at < (current_date + 1)::timestamp at time zone 'UTC'),0)::bigint
    into v_receipts_total,v_receipt_count,v_receipts_period,v_receipts_today
  from public.payments p
  where p.status='validated'
    and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC');

  select coalesce(sum(e.amount),0)::bigint, count(*)::bigint,
         coalesce(sum(e.amount) filter (
           where e.expense_date <= current_date
             and (p_from is null or e.expense_date >= p_from)
             and (p_to is null or e.expense_date <= p_to)
         ),0)::bigint
    into v_expenses_total,v_expense_count,v_expenses_period
  from public.expenses e where e.status='validated' and e.expense_date <= current_date;

  select coalesce(sum(coalesce(c.gross_amount,c.amount_due)),0)::bigint,
         coalesce(sum(coalesce(c.discount_amount,0)),0)::bigint,
         coalesce(sum(c.amount_due),0)::bigint,
         coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint,
         coalesce(sum(least(coalesce(paid.amount_paid,0),c.amount_due)),0)::bigint
    into v_fee_gross,v_discount,v_fee_net,v_balance_due,v_paid_allocated
  from public.student_charges c
  left join lateral (
    select coalesce(sum(pa.amount),0)::bigint as amount_paid
    from public.payment_allocations pa
    join public.payments p on p.id=pa.payment_id and p.status='validated'
      and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
    where pa.charge_id=c.id
  ) paid on true
  where c.status='validated';

  select coalesce(sum(b.balance),0)::bigint into v_treasury
  from public.get_treasury_balances() b;

  select count(*)::bigint,coalesce(sum(e.amount),0)::bigint
    into v_open_drafts,v_open_drafts_amount
  from public.expenses e where e.status='draft';

  return jsonb_build_object(
    'receipts_total',v_receipts_total,
    'receipts_period',v_receipts_period,
    'receipts_today',v_receipts_today,
    'validated_receipt_count',v_receipt_count,
    'expenses_total',v_expenses_total,
    'expenses_period',v_expenses_period,
    'validated_expense_count',v_expense_count,
    'fees_gross',v_fee_gross,
    'discounts_total',v_discount,
    'fees_net',v_fee_net,
    'payments_allocated',v_paid_allocated,
    'outstanding_balance',v_balance_due,
    'treasury_total',v_treasury,
    'draft_expense_count',v_open_drafts,
    'draft_expense_total',v_open_drafts_amount
  );
end;
$$;

revoke all on function public.get_financial_summary(date,date) from public, anon;
grant execute on function public.get_financial_summary(date,date) to authenticated;

-- Vue d'ensemble du tableau de bord avec les recettes mensuelles calculées en base.
create or replace function public.get_financial_overview(p_months integer default 6)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_year_id uuid;
  v_year_label text;
  v_students bigint := 0;
  v_enrollments bigint := 0;
  v_months integer := least(greatest(coalesce(p_months,6),1),12);
  v_month_data jsonb;
  v_summary jsonb;
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé au tableau de bord financier.' using errcode = '42501';
  end if;

  select sy.id,sy.label into v_year_id,v_year_label
  from public.school_years sy where sy.is_current=true limit 1;

  select count(*)::bigint into v_students from public.students;
  if v_year_id is not null then
    select count(*)::bigint into v_enrollments
    from public.enrollments e
    where e.school_year_id=v_year_id and e.status in ('inscrit','reinscrit');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'label',case extract(month from month_start)::integer
        when 1 then 'Jan' when 2 then 'Fév' when 3 then 'Mar' when 4 then 'Avr'
        when 5 then 'Mai' when 6 then 'Juin' when 7 then 'Juil' when 8 then 'Août'
        when 9 then 'Sep' when 10 then 'Oct' when 11 then 'Nov' else 'Déc' end,
      'key',to_char(month_start,'YYYY-MM'),
      'amount',coalesce(month_total.amount,0)
    ) order by month_start
  ),'[]'::jsonb) into v_month_data
  from (
    select (date_trunc('month',current_date)::date - ((v_months - 1 - gs.n) * interval '1 month'))::date as month_start
    from generate_series(0,v_months-1) as gs(n)
  ) months
  left join lateral (
    select coalesce(sum(p.amount),0)::bigint as amount
    from public.payments p
    where p.status='validated'
      and p.paid_at >= months.month_start::timestamp at time zone 'UTC'
      and p.paid_at < (months.month_start + interval '1 month')::timestamp at time zone 'UTC'
      and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
  ) month_total on true;

  v_summary := public.get_financial_summary(null::date,null::date);
  return jsonb_build_object(
    'students',v_students,
    'enrollments',v_enrollments,
    'school_year_label',coalesce(v_year_label,'Aucune année active'),
    'months',v_month_data,
    'financial',v_summary
  );
end;
$$;

revoke all on function public.get_financial_overview(integer) from public, anon;
grant execute on function public.get_financial_overview(integer) to authenticated;

commit;
