-- EPC BETHEL - Etape 2 : encaissements, affectation automatique, reçus et annulations contrôlées.
-- A exécuter après les migrations 001 à 005 sur un projet Supabase de développement.

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
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where p.status='validated'),0),0)::bigint
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

revoke all on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) from public;
grant execute on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) to authenticated;

-- Annulation via cancel_payment() existante : motif obligatoire, écriture de contrepassation
-- et conservation de l'historique du reçu. Ne pas supprimer les paiements validés.
