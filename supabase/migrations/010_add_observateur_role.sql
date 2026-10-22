-- EPC BETHEL — ajoute le rôle de consultation seule.
-- À appliquer après les migrations 001 à 009.
alter type public.app_role add value if not exists 'observateur';
-- Utilisé par le niveau d’accès Modification (tous les modules métier, sans administration des comptes).
alter type public.app_role add value if not exists 'modification';
