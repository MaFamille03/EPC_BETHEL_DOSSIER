-- EPC BETHEL — code d’accès administrateur configurable depuis Paramètres.
-- Exécuter une seule fois après la migration 014.
BEGIN;
CREATE TABLE IF NOT EXISTS public.admin_access_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id = true),
  registration_code_hash text,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_access_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.admin_access_settings FROM anon, authenticated, PUBLIC;
INSERT INTO public.admin_access_settings (id, registration_code_hash)
VALUES (true, NULL)
ON CONFLICT (id) DO NOTHING;
COMMIT;
