-- ============================================
-- SafeZone - Archivo automático de reportes
-- Mueve reportes > 7 días a la tabla de archivo
-- ============================================

-- 1. Tabla de Reportes Archivados (misma estructura que reports + archived_at)
CREATE TABLE IF NOT EXISTS archived_reports (
  id UUID PRIMARY KEY,
  user_code TEXT NOT NULL,
  zone INTEGER NOT NULL,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  image_url TEXT,
  video_url TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  address TEXT,
  tag TEXT NOT NULL,
  status TEXT DEFAULT 'activo',
  created_at TIMESTAMPTZ NOT NULL,
  shield_count INTEGER DEFAULT 0,
  alert_count INTEGER DEFAULT 0,
  check_count INTEGER DEFAULT 0,
  archived_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para búsqueda rápida en archivo
CREATE INDEX IF NOT EXISTS idx_archived_reports_zone ON archived_reports(zone);
CREATE INDEX IF NOT EXISTS idx_archived_reports_category ON archived_reports(category);
CREATE INDEX IF NOT EXISTS idx_archived_reports_created_at ON archived_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_archived_reports_archived_at ON archived_reports(archived_at DESC);

-- Políticas RLS para archived_reports
ALTER TABLE archived_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Archived reports legible por cualquiera" ON archived_reports
  FOR SELECT USING (true);

CREATE POLICY "Archived reports insertable por cualquiera" ON archived_reports
  FOR INSERT WITH CHECK (true);

-- 2. Tabla de Reacciones Archivadas (para mantener integridad)
CREATE TABLE IF NOT EXISTS archived_reactions (
  id UUID PRIMARY KEY,
  report_id UUID NOT NULL,
  user_code TEXT NOT NULL,
  reaction_type TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  archived_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_archived_reactions_report_id ON archived_reactions(report_id);

ALTER TABLE archived_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Archived reactions legible por cualquiera" ON archived_reactions
  FOR SELECT USING (true);

CREATE POLICY "Archived reactions insertable por cualquiera" ON archived_reactions
  FOR INSERT WITH CHECK (true);

-- 3. Función: Archivar reportes antiguos (> 7 días)
-- Elimina TODAS las versiones viejas de archive_old_reports (algunas
-- versiones anteriores usaban una columna surprise_count que ya no existe)
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT oid::regprocedure AS signature
    FROM pg_proc
    WHERE proname = 'archive_old_reports'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION ' || f.signature || ' CASCADE';
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION archive_old_reports()
RETURNS INTEGER AS $$
DECLARE
  archived_count INTEGER := 0;
  cutoff_date TIMESTAMPTZ := NOW() - INTERVAL '7 days';
BEGIN
  -- Mover reacciones de reportes antiguos a archived_reactions
  INSERT INTO archived_reactions (id, report_id, user_code, reaction_type, created_at, archived_at)
  SELECT r.id, r.report_id, r.user_code, r.reaction_type, r.created_at, NOW()
  FROM reactions r
  INNER JOIN reports re ON re.id = r.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  -- Eliminar reacciones de reportes que serán archivados
  DELETE FROM reactions r
  USING reports re
  WHERE re.id = r.report_id AND re.created_at < cutoff_date;

  -- Mover reportes antiguos a archived_reports
  INSERT INTO archived_reports (
    id, user_code, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    archived_at
  )
  SELECT 
    id, user_code, zone, category, description,
    image_url, video_url, latitude, longitude, address,
    tag, status, created_at, shield_count, alert_count, check_count,
    NOW()
  FROM reports
  WHERE created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS archived_count = ROW_COUNT;

  -- Eliminar reportes antiguos de la tabla principal
  DELETE FROM reports WHERE created_at < cutoff_date;

  RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
