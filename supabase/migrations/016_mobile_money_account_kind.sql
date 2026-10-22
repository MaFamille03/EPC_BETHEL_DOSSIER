-- Autorise la distinction explicite des comptes Mobile Money dans la trésorerie.
-- Cette migration ajoute une valeur d'énumération sans modifier les comptes ni les mouvements existants.
alter type public.account_kind add value if not exists 'mobile_money';
