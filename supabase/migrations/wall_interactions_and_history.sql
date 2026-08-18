-- SafeZone - Muro: reacciones únicas, Realtime e historial de comentarios.
-- IMPORTANTE: revisar y ejecutar manualmente en Supabase SQL Editor.
-- No elimina reportes históricos: mantiene el archivo existente de 7 días.
-- Compatible con el flujo legado: user_code es la identidad persistida localmente.

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
  reaction_type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE archived_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Archived reactions legible por cualquiera"
  ON archived_reactions;
CREATE POLICY "Archived reactions legible por cualquiera"
  ON archived_reactions FOR SELECT USING (true);
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
  id, report_id, user_code, reaction_type, created_at, archived_at
)
SELECT
  r.id, r.report_id, r.user_code,
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

-- La app legado escribe reacciones directamente usando user_code.
DROP POLICY IF EXISTS "Reactions insertable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions actualizable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions eliminable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions legible por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions legibles por usuarios" ON reactions;
CREATE POLICY "Reactions legibles por usuarios" ON reactions FOR SELECT USING (true);
CREATE POLICY "Reactions insertable por cualquiera" ON reactions FOR INSERT WITH CHECK (true);
CREATE POLICY "Reactions actualizable por cualquiera" ON reactions FOR UPDATE USING (true);
CREATE POLICY "Reactions eliminable por cualquiera" ON reactions FOR DELETE USING (true);

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
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_archived_report_comments_report_id
  ON archived_report_comments(report_id);

ALTER TABLE archived_report_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Archived comments legibles por cualquiera"
  ON archived_report_comments;
CREATE POLICY "Archived comments legibles por cualquiera"
  ON archived_report_comments FOR SELECT USING (true);
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
  ON archived_reports FOR SELECT USING (true);
DROP POLICY IF EXISTS "Archived reports insertable por cualquiera"
  ON archived_reports;

-- reports ya almacena este contador. Sin esta columna el registro archivado no
-- preservaba completamente el reporte original.
ALTER TABLE archived_reports
  ADD COLUMN IF NOT EXISTS surprise_count INTEGER DEFAULT 0;

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
    id, report_id, user_code,
    reaction_type, created_at, archived_at
  )
  SELECT
    r.id, r.report_id, r.user_code,
    r.reaction_type, r.created_at, NOW()
  FROM public.reactions r
  INNER JOIN public.reports re ON re.id = r.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.archived_report_comments (
    id, report_id, user_code,
    comment_text, created_at, archived_at
  )
  SELECT
    c.id, c.report_id, c.user_code,
    c.comment_text, c.created_at, NOW()
  FROM public.report_comments c
  INNER JOIN public.reports re ON re.id = c.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  DELETE FROM public.reactions r
  USING public.reports re
  WHERE r.report_id = re.id AND re.created_at < cutoff_date;

  INSERT INTO public.archived_reports (
    id, user_code, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    surprise_count,
    archived_at
  )
  SELECT
    id, user_code, zone, category, description,
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

-- Compatibilidad temporal: HomeScreen todavia solicita este archivado.
REVOKE ALL ON FUNCTION public.archive_old_reports() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_old_reports() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archive_old_reports() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
