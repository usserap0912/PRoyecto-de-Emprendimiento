-- SafeZone - Muro: reacciones únicas, Realtime e historial de comentarios.
-- IMPORTANTE: revisar y ejecutar manualmente en Supabase SQL Editor.
-- No elimina reportes históricos: mantiene el archivo existente de 7 días.
-- Ejecutar DESPUES de anonymous_auth_identity.sql. user_code continua siendo
-- el alias visible, pero auth.uid() es la unica identidad autorizante.

BEGIN;

-- Convierte los identificadores visuales antiguos al emoji que representaban.
UPDATE reactions
SET reaction_type = CASE reaction_type
  WHEN 'shield' THEN '🛡️'
  WHEN 'alert' THEN '⚠️'
  WHEN 'check' THEN '🙏'
  WHEN 'pray' THEN '🙏'
  WHEN 'surprised' THEN '😮'
  ELSE reaction_type
END;

CREATE TABLE IF NOT EXISTS archived_reactions (
  id UUID PRIMARY KEY,
  report_id UUID NOT NULL,
  user_code TEXT NOT NULL,
  auth_user_id UUID,
  reaction_type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE archived_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE archived_reactions
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
DROP POLICY IF EXISTS "Archived reactions legible por cualquiera"
  ON archived_reactions;
CREATE POLICY "Archived reactions legible por cualquiera"
  ON archived_reactions FOR SELECT TO authenticated USING (true);
-- El historial lo escribe exclusivamente archive_old_reports() o esta
-- migración. Un cliente nunca debe poder fabricar evidencia histórica.
DROP POLICY IF EXISTS "Archived reactions insertable por cualquiera"
  ON archived_reactions;

-- Conserva solo la reacción más reciente si datos heredados contienen varias
-- reacciones del mismo usuario en una publicación.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY report_id, user_code
      ORDER BY created_at DESC, id DESC
    ) AS position
  FROM reactions
)
INSERT INTO archived_reactions (
  id, report_id, user_code, auth_user_id, reaction_type, created_at, archived_at
)
SELECT
  r.id, r.report_id, r.user_code, r.auth_user_id,
  r.reaction_type, r.created_at, NOW()
FROM reactions r
INNER JOIN ranked d ON d.id = r.id
WHERE d.position > 1
ON CONFLICT (id) DO NOTHING;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY report_id, user_code
      ORDER BY created_at DESC, id DESC
    ) AS position
  FROM reactions
)
DELETE FROM reactions
WHERE id IN (SELECT id FROM ranked WHERE position > 1);

ALTER TABLE reactions
  DROP CONSTRAINT IF EXISTS reactions_report_id_user_code_reaction_type_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.reactions'::regclass
      AND conname = 'reactions_one_per_user_per_report'
  ) THEN
    ALTER TABLE reactions
      ADD CONSTRAINT reactions_one_per_user_per_report
      UNIQUE (report_id, user_code);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.reactions'::regclass
      AND conname = 'reactions_one_per_auth_user_per_report'
  ) THEN
    ALTER TABLE reactions
      ADD CONSTRAINT reactions_one_per_auth_user_per_report
      UNIQUE (report_id, auth_user_id);
  END IF;
END $$;

-- La app usa toggle_report_reaction(), por lo que no necesita escritura directa
-- sobre reactions. El RPC deriva alias y propietario exclusivamente de auth.uid().
DROP POLICY IF EXISTS "Reactions insertable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions actualizable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions eliminable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions legible por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions legibles por usuarios" ON reactions;
CREATE POLICY "Reactions legibles por usuarios" ON reactions
  FOR SELECT TO authenticated USING (true);

-- Operación atómica: mismo emoji lo retira; uno diferente reemplaza al actual.
CREATE OR REPLACE FUNCTION toggle_report_reaction(
  p_report_id UUID,
  p_reaction TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
-- SECURITY DEFINER es necesario mientras las escrituras directas permanecen
-- cerradas. La función queda deliberadamente acotada a una sola reacción.
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  current_user_code TEXT;
  current_reaction TEXT;
  normalized_reaction TEXT;
BEGIN
  IF current_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT user_code INTO current_user_code
  FROM public.profiles
  WHERE auth_user_id = current_auth_user_id;
  IF current_user_code IS NULL THEN
    RAISE EXCEPTION 'linked profile required' USING ERRCODE = '42501';
  END IF;

  IF p_reaction IS NULL OR BTRIM(p_reaction) = '' OR CHAR_LENGTH(p_reaction) > 32 THEN
    RAISE EXCEPTION 'invalid reaction';
  END IF;

  normalized_reaction := CASE BTRIM(p_reaction)
    WHEN 'shield' THEN '🛡️'
    WHEN 'alert' THEN '⚠️'
    WHEN 'check' THEN '🙏'
    WHEN 'pray' THEN '🙏'
    WHEN 'surprised' THEN '😮'
    ELSE BTRIM(p_reaction)
  END;

  SELECT reaction_type
  INTO current_reaction
  FROM public.reactions
  WHERE report_id = p_report_id
    AND auth_user_id = current_auth_user_id;

  IF current_reaction = normalized_reaction THEN
    DELETE FROM public.reactions
    WHERE report_id = p_report_id
      AND auth_user_id = current_auth_user_id;
    RETURN jsonb_build_object('action', 'removed', 'reaction_type', NULL);
  END IF;

  INSERT INTO public.reactions (
    report_id, user_code, auth_user_id, reaction_type, created_at
  )
  VALUES (
    p_report_id, current_user_code, current_auth_user_id,
    normalized_reaction, NOW()
  )
  ON CONFLICT (report_id, auth_user_id)
  DO UPDATE SET
    reaction_type = EXCLUDED.reaction_type,
    created_at = NOW();

  RETURN jsonb_build_object(
    'action', 'set',
    'reaction_type', normalized_reaction
  );
END;
$$;

DROP FUNCTION IF EXISTS public.toggle_report_reaction(UUID, TEXT, TEXT);
REVOKE ALL ON FUNCTION public.toggle_report_reaction(UUID, TEXT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.toggle_report_reaction(UUID, TEXT)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_report_reaction(UUID, TEXT)
  TO authenticated;

-- La implementación heredada no recalculaba contadores al cambiar un emoji
-- mediante UPDATE. Se conserva compatibilidad con pantallas antiguas.
DROP TRIGGER IF EXISTS trigger_update_reaction_counts ON reactions;
CREATE TRIGGER trigger_update_reaction_counts
  AFTER INSERT OR UPDATE OR DELETE ON reactions
  FOR EACH ROW
  EXECUTE FUNCTION update_report_reaction_counts();

ALTER TABLE reactions REPLICA IDENTITY FULL;
ALTER TABLE report_comments REPLICA IDENTITY FULL;

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE reactions;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE report_comments;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;

CREATE INDEX IF NOT EXISTS idx_reports_zone_created_at
  ON reports(zone, created_at DESC);

-- El archivo anterior no copiaba comentarios antes del DELETE con CASCADE.
CREATE TABLE IF NOT EXISTS archived_report_comments (
  id UUID PRIMARY KEY,
  report_id UUID NOT NULL,
  user_code TEXT NOT NULL,
  auth_user_id UUID,
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_archived_report_comments_report_id
  ON archived_report_comments(report_id);

ALTER TABLE archived_report_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE archived_report_comments
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
DROP POLICY IF EXISTS "Archived comments legibles por cualquiera"
  ON archived_report_comments;
CREATE POLICY "Archived comments legibles por cualquiera"
  ON archived_report_comments FOR SELECT TO authenticated USING (true);
-- Los clientes conservan lectura, pero no pueden inyectar comentarios en el
-- historial. archive_old_reports() escribe como definidor.
DROP POLICY IF EXISTS "Archived comments insertables por cualquiera"
  ON archived_report_comments;

-- archived_reports es creado por la migración histórica anterior. Se conserva
-- la lectura existente y se retira únicamente la inserción pública.
ALTER TABLE archived_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Archived reports legible por cualquiera"
  ON archived_reports;
CREATE POLICY "Archived reports legible por cualquiera"
  ON archived_reports FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Archived reports insertable por cualquiera"
  ON archived_reports;

-- reports ya almacena este contador. Sin esta columna el registro archivado no
-- preservaba completamente el reporte original.
ALTER TABLE archived_reports
  ADD COLUMN IF NOT EXISTS surprise_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;

CREATE OR REPLACE FUNCTION archive_old_reports()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  archived_count INTEGER := 0;
  cutoff_date TIMESTAMPTZ := NOW() - INTERVAL '7 days';
BEGIN
  INSERT INTO public.archived_reactions (
    id, report_id, user_code, auth_user_id,
    reaction_type, created_at, archived_at
  )
  SELECT
    r.id, r.report_id, r.user_code, r.auth_user_id,
    r.reaction_type, r.created_at, NOW()
  FROM public.reactions r
  INNER JOIN public.reports re ON re.id = r.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.archived_report_comments (
    id, report_id, user_code, auth_user_id,
    comment_text, created_at, archived_at
  )
  SELECT
    c.id, c.report_id, c.user_code, c.auth_user_id,
    c.comment_text, c.created_at, NOW()
  FROM public.report_comments c
  INNER JOIN public.reports re ON re.id = c.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  DELETE FROM public.reactions r
  USING public.reports re
  WHERE r.report_id = re.id AND re.created_at < cutoff_date;

  INSERT INTO public.archived_reports (
    id, user_code, auth_user_id, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    surprise_count,
    archived_at
  )
  SELECT
    id, user_code, auth_user_id, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    surprise_count,
    NOW()
  FROM public.reports
  WHERE created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS archived_count = ROW_COUNT;

  -- ON DELETE CASCADE limpia comentarios activos después de archivarlos.
  DELETE FROM public.reports WHERE created_at < cutoff_date;

  RETURN archived_count;
END;
$$;

-- Compatibilidad temporal: HomeScreen todavia solicita este archivado. Cualquier
-- usuario autenticado podria invocarlo; mover a cron/servidor antes de produccion.
REVOKE ALL ON FUNCTION public.archive_old_reports() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_old_reports() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archive_old_reports() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
