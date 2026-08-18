-- SafeZone: Muro global legado (User-XXXX), reacciones y comentarios Realtime.
-- REVISAR Y EJECUTAR MANUALMENTE. No usa ni agrega Anonymous Auth.

BEGIN;

-- Conserva una sola reacción activa por usuario y publicación.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY report_id, user_code
      ORDER BY created_at DESC, id DESC
    ) AS position
  FROM public.reactions
)
INSERT INTO public.archived_reactions (
  id, report_id, user_code, reaction_type, created_at, archived_at
)
SELECT
  r.id, r.report_id, r.user_code, r.reaction_type, r.created_at, NOW()
FROM public.reactions r
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
  FROM public.reactions
)
DELETE FROM public.reactions
WHERE id IN (SELECT id FROM ranked WHERE position > 1);

ALTER TABLE public.reactions
  DROP CONSTRAINT IF EXISTS reactions_report_id_user_code_reaction_type_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.reactions'::regclass
      AND conname = 'reactions_one_per_user_per_report'
  ) THEN
    ALTER TABLE public.reactions
      ADD CONSTRAINT reactions_one_per_user_per_report
      UNIQUE (report_id, user_code);
  END IF;
END $$;

-- Acceso legado mediante user_code. Flutter confirma cada INSERT/DELETE.
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Reactions legibles por usuarios" ON public.reactions;
DROP POLICY IF EXISTS "Reactions legible por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions insertable por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions actualizable por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions eliminable por cualquiera" ON public.reactions;
CREATE POLICY "Reactions legibles por usuarios"
  ON public.reactions FOR SELECT USING (true);
CREATE POLICY "Reactions insertable por cualquiera"
  ON public.reactions FOR INSERT WITH CHECK (true);
CREATE POLICY "Reactions actualizable por cualquiera"
  ON public.reactions FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Reactions eliminable por cualquiera"
  ON public.reactions FOR DELETE USING (true);

ALTER TABLE public.report_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Comments legible por cualquiera" ON public.report_comments;
DROP POLICY IF EXISTS "Comments insertable por cualquiera" ON public.report_comments;
CREATE POLICY "Comments legible por cualquiera"
  ON public.report_comments FOR SELECT USING (true);
CREATE POLICY "Comments insertable por cualquiera"
  ON public.report_comments FOR INSERT WITH CHECK (true);

-- El backend actual aún no expone esta tabla histórica.
CREATE TABLE IF NOT EXISTS public.archived_report_comments (
  id UUID PRIMARY KEY,
  report_id UUID NOT NULL,
  user_code TEXT NOT NULL,
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_archived_report_comments_report_id
  ON public.archived_report_comments(report_id);
ALTER TABLE public.archived_report_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Archived comments legibles por cualquiera"
  ON public.archived_report_comments;
CREATE POLICY "Archived comments legibles por cualquiera"
  ON public.archived_report_comments FOR SELECT USING (true);

ALTER TABLE public.archived_reports
  ADD COLUMN IF NOT EXISTS surprise_count INTEGER DEFAULT 0;

-- UPDATE/DELETE deben incluir la fila completa en eventos Realtime.
ALTER TABLE public.reactions REPLICA IDENTITY FULL;
ALTER TABLE public.report_comments REPLICA IDENTITY FULL;
ALTER TABLE public.reports REPLICA IDENTITY FULL;
ALTER TABLE public.sos_alerts REPLICA IDENTITY FULL;

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reports;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reactions;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.report_comments;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- Mantiene comentarios al archivar reportes mayores de siete días.
CREATE OR REPLACE FUNCTION public.archive_old_reports()
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
    id, report_id, user_code, reaction_type, created_at, archived_at
  )
  SELECT
    r.id, r.report_id, r.user_code, r.reaction_type, r.created_at, NOW()
  FROM public.reactions r
  INNER JOIN public.reports re ON re.id = r.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.archived_report_comments (
    id, report_id, user_code, comment_text, created_at, archived_at
  )
  SELECT
    c.id, c.report_id, c.user_code, c.comment_text, c.created_at, NOW()
  FROM public.report_comments c
  INNER JOIN public.reports re ON re.id = c.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.archived_reports (
    id, user_code, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    surprise_count, archived_at
  )
  SELECT
    id, user_code, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    surprise_count, NOW()
  FROM public.reports
  WHERE created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS archived_count = ROW_COUNT;
  DELETE FROM public.reports WHERE created_at < cutoff_date;
  RETURN archived_count;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_old_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_old_reports() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
