-- EPC BETHEL — Distinction des comptes de trésorerie et création sécurisée.
-- À appliquer après les migrations 001 à 020 sur une base de développement,
-- puis à valider avant production.

alter type public.account_kind add value if not exists 'mobile_money';

alter table public.cash_accounts
  add column if not exists provider_name text;

comment on column public.cash_accounts.provider_name is
  'Opérateur du portefeuille Mobile Money (ex. Orange Money, MTN MoMo).';

create or replace function public.create_cash_account(
  p_code text,
  p_name text,
  p_kind public.account_kind,
  p_bank_name text default null,
  p_provider_name text default null,
  p_opening_balance bigint default 0,
  p_opening_date date default current_date
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_account_id uuid;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_name text := trim(coalesce(p_name, ''));
begin
  if not public.has_any_role(array['admin']::public.app_role[]) then
    raise exception 'Seul un administrateur peut créer un compte financier.' using errcode = '42501';
  end if;
  if v_code = '' or v_name = '' then
    raise exception 'Le code et le nom du compte sont obligatoires.';
  end if;
  if v_code !~ '^[A-Z0-9_-]{2,30}$' then
    raise exception 'Le code doit contenir 2 à 30 caractères : lettres, chiffres, tirets ou soulignés.';
  end if;
  if p_kind::text not in ('cash', 'bank', 'mobile_money') then
    raise exception 'Type de compte non pris en charge.';
  end if;
  if p_opening_balance is null or p_opening_balance < 0 then
    raise exception 'Le solde initial doit être un entier positif ou nul.';
  end if;
  if p_opening_date is null then
    raise exception 'La date d’ouverture est obligatoire.';
  end if;
  if p_kind::text = 'mobile_money' and nullif(trim(coalesce(p_provider_name, '')), '') is null then
    raise exception 'L’opérateur Mobile Money est obligatoire.';
  end if;
  if exists(select 1 from public.cash_accounts a where a.code = v_code) then
    raise exception 'Ce code de compte existe déjà.' using errcode = '23505';
  end if;

  insert into public.cash_accounts(
    code, name, kind, bank_name, provider_name,
    opening_balance, opening_date, is_active, created_by
  ) values (
    v_code, v_name, p_kind,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_provider_name, '')), ''),
    p_opening_balance, p_opening_date, true, v_uid
  ) returning id into v_account_id;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (
    v_uid, 'create_cash_account', 'cash_accounts', v_account_id::text,
    jsonb_build_object(
      'code', v_code, 'name', v_name, 'kind', p_kind::text,
      'opening_balance', p_opening_balance, 'opening_date', p_opening_date
    )
  );
  return v_account_id;
end;
$$;

revoke all on function public.create_cash_account(text,text,public.account_kind,text,text,bigint,date) from public, anon;
grant execute on function public.create_cash_account(text,text,public.account_kind,text,text,bigint,date) to authenticated;


-- Empêche d'affecter un encaissement ou une dépense au mauvais type de compte.
-- 'autre' reste libre, les modes Mobile Money/Espèces/Virement/Chèque sont typés.
create or replace function public.check_treasury_account_method_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text;
  v_account_id uuid;
  v_account_kind public.account_kind;
begin
  if tg_table_name = 'payments' then
    v_method := new.method::text;
    v_account_id := new.account_id;
  elsif tg_table_name = 'expenses' then
    v_method := new.payment_method::text;
    v_account_id := new.account_id;
  else
    raise exception 'Table non prise en charge par le contrôle de compte.';
  end if;

  select a.kind into v_account_kind
  from public.cash_accounts a
  where a.id = v_account_id and a.is_active = true;
  if not found then
    raise exception 'Le compte choisi est inactif ou introuvable.';
  end if;

  if v_method = 'especes' and v_account_kind::text <> 'cash' then
    raise exception 'Pour un paiement en espèces, choisissez un compte de caisse.';
  elsif v_method = 'mobile_money' and v_account_kind::text <> 'mobile_money' then
    raise exception 'Pour un paiement Mobile Money, choisissez un portefeuille Mobile Money.';
  elsif v_method in ('virement', 'cheque') and v_account_kind::text <> 'bank' then
    raise exception 'Pour un virement ou un chèque, choisissez un compte bancaire.';
  end if;

  return new;
end;
$$;

revoke all on function public.check_treasury_account_method_match() from public, anon, authenticated;

drop trigger if exists payments_account_method_match on public.payments;
create trigger payments_account_method_match
before insert or update of method, account_id on public.payments
for each row execute function public.check_treasury_account_method_match();

drop trigger if exists expenses_account_method_match on public.expenses;
create trigger expenses_account_method_match
before insert or update of payment_method, account_id on public.expenses
for each row execute function public.check_treasury_account_method_match();
