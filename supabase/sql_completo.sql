-- ============================================================
-- ⚠️ REGLA DEL PROYECTO: ESTE ES EL ARCHIVO ÚNICO MAESTRO DE SQL.
-- Todo SQL nuevo (tablas, funciones, columnas, cambios) se agrega
-- SIEMPRE aquí, al final, con su comentario de sección.
-- NO crear archivos SQL separados.
-- ============================================================


-- ============================================================
-- PARTE 1 — ESQUEMA BASE (14 ZONAS + COMENTARIOS + EMOJIS)
-- (Lo que me pasaste: esquema base NUEVO de la app)
-- ============================================================
-- ============================================
-- SafeZone - Esquema de Base de Datos Supabase
-- Collique, Comas - Red Vecinal de Seguridad
-- ============================================

-- 1. Tabla de Perfiles (usuarios anónimos - Ampliado a 14 Zonas)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT UNIQUE NOT NULL,
  zone INTEGER NOT NULL CHECK (zone >= 1 AND zone <= 14), -- SOPORTA LAS 14 ZONAS
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE
);

-- Index para búsqueda rápida por código de usuario
CREATE INDEX IF NOT EXISTS idx_profiles_user_code ON profiles(user_code);
CREATE INDEX IF NOT EXISTS idx_profiles_zone ON profiles(zone);

-- 2. Tabla de Reportes
CREATE TABLE IF NOT EXISTS reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  zone INTEGER NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('robo', 'sos', 'sospechoso', 'extorsion', 'alumbrado', 'otros')),
  description TEXT NOT NULL,
  image_url TEXT,
  video_url TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  address TEXT,
  tag TEXT NOT NULL CHECK (tag IN ('rojo', 'amarillo', 'verde')),
  status TEXT DEFAULT 'activo' CHECK (status IN ('activo', 'resuelto')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  shield_count INTEGER DEFAULT 0,
  alert_count INTEGER DEFAULT 0,
  check_count INTEGER DEFAULT 0,
  surprise_count INTEGER DEFAULT 0 -- NUEVO: Contador para emoji de sorpresa (😮)
);

-- Índices para reportes
CREATE INDEX IF NOT EXISTS idx_reports_zone ON reports(zone);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_tag ON reports(tag);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON reports(created_at DESC);

-- ⚠️ COMPATIBILIDAD: si tu tabla reports ya existía SIN surprise_count,
-- esta línea la agrega. (No rompe nada si ya existe.)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS surprise_count INTEGER DEFAULT 0;

-- 3. Tabla de Reacciones (Adaptada para Emojis Flexibles)
CREATE TABLE IF NOT EXISTS reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  reaction_type TEXT NOT NULL, -- Soporta texto directo para emojis (🛡️, ⚠️, 😮, 🙏)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(report_id, user_code, reaction_type)
);

CREATE INDEX IF NOT EXISTS idx_reactions_report_id ON reactions(report_id);

-- 4. Nueva Tabla de Comentarios en Muro
CREATE TABLE IF NOT EXISTS report_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_comments_report_id ON report_comments(report_id);

-- 5. Tabla de Mensajes del Chat
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at ASC);

-- 6. Tabla de Alertas S.O.S.
CREATE TABLE IF NOT EXISTS sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  address TEXT,
  status TEXT DEFAULT 'activo' CHECK (status IN ('activo', 'cancelado', 'atendido')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  finished_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sos_alerts_status ON sos_alerts(status);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_created_at ON sos_alerts(created_at DESC);

-- ============================================
-- POLÍTICAS DE SEGURIDAD (Row Level Security)
-- ============================================

-- Habilitar RLS en todas las tablas
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;

-- 🛡️ ELIMINAR POLÍTICAS ANTIGUAS SI YA EXISTEN PARA EVITAR EL ERROR DE DUPLICADO
DROP POLICY IF EXISTS "Profiles insertable por cualquiera" ON profiles;
DROP POLICY IF EXISTS "Profiles legibles por cualquiera" ON profiles;
DROP POLICY IF EXISTS "Reports insertable por cualquiera" ON reports;
DROP POLICY IF EXISTS "Reports legibles por cualquiera" ON reports;
DROP POLICY IF EXISTS "Reports actualizable por cualquiera" ON reports;
DROP POLICY IF EXISTS "Reactions insertable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions legible por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Reactions eliminable por cualquiera" ON reactions;
DROP POLICY IF EXISTS "Comments insertable por cualquiera" ON report_comments;
DROP POLICY IF EXISTS "Comments legible por cualquiera" ON report_comments;
DROP POLICY IF EXISTS "Chat messages insertable por cualquiera" ON chat_messages;
DROP POLICY IF EXISTS "Chat messages legible por cualquiera" ON chat_messages;
DROP POLICY IF EXISTS "SOS alerts insertable por cualquiera" ON sos_alerts;
DROP POLICY IF EXISTS "SOS alerts legible por cualquiera" ON sos_alerts;
DROP POLICY IF EXISTS "SOS alerts actualizable por cualquiera" ON sos_alerts;

-- Crear políticas globales para accesos anónimos
CREATE POLICY "Profiles insertable por cualquiera" ON profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "Profiles legibles por cualquiera" ON profiles FOR SELECT USING (true);
CREATE POLICY "Reports insertable por cualquiera" ON reports FOR INSERT WITH CHECK (true);
CREATE POLICY "Reports legibles por cualquiera" ON reports FOR SELECT USING (true);
CREATE POLICY "Reports actualizable por cualquiera" ON reports FOR UPDATE USING (true);
CREATE POLICY "Reactions insertable por cualquiera" ON reactions FOR INSERT WITH CHECK (true);
CREATE POLICY "Reactions legible por cualquiera" ON reactions FOR SELECT USING (true);
CREATE POLICY "Reactions eliminable por cualquiera" ON reactions FOR DELETE USING (true);
CREATE POLICY "Comments insertable por cualquiera" ON report_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Comments legible por cualquiera" ON report_comments FOR SELECT USING (true);
CREATE POLICY "Chat messages insertable por cualquiera" ON chat_messages FOR INSERT WITH CHECK (true);
CREATE POLICY "Chat messages legible por cualquiera" ON chat_messages FOR SELECT USING (true);
CREATE POLICY "SOS alerts insertable por cualquiera" ON sos_alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "SOS alerts legible por cualquiera" ON sos_alerts FOR SELECT USING (true);
CREATE POLICY "SOS alerts actualizable por cualquiera" ON sos_alerts FOR UPDATE USING (true);

-- ============================================
-- FUNCIONES Y TRIGGERS CONFIGURADOS
-- ============================================

-- Función: Actualizar contadores de reacciones filtrando por Emojis
CREATE OR REPLACE FUNCTION update_report_reaction_counts()
RETURNS TRIGGER AS $$
DECLARE
  target_report_id UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target_report_id := OLD.report_id;
  ELSE
    target_report_id := NEW.report_id;
  END IF;

  UPDATE reports
  SET
    shield_count = (SELECT COUNT(*) FROM reactions WHERE report_id = target_report_id AND (reaction_type = 'shield' OR reaction_type = '🛡️')),
    alert_count = (SELECT COUNT(*) FROM reactions WHERE report_id = target_report_id AND (reaction_type = 'alert' OR reaction_type = '⚠️')),
    check_count = (SELECT COUNT(*) FROM reactions WHERE report_id = target_report_id AND (reaction_type = 'check' OR reaction_type = '🙏')),
    surprise_count = (SELECT COUNT(*) FROM reactions WHERE report_id = target_report_id AND reaction_type = '😮')
  WHERE id = target_report_id;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Eliminar el disparador antiguo si ya existe para evitar errores
DROP TRIGGER IF EXISTS trigger_update_reaction_counts ON reactions;

CREATE TRIGGER trigger_update_reaction_counts
  AFTER INSERT OR DELETE ON reactions
  FOR EACH ROW
  EXECUTE FUNCTION update_report_reaction_counts();

-- Función: Generar código de usuario único
CREATE OR REPLACE FUNCTION generate_user_code()
RETURNS TEXT AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  nums TEXT := '0123456789';
  code TEXT;
BEGIN
  code := 'User-' ||
    substr(chars, floor(random() * length(chars) + 1)::integer, 1) ||
    substr(nums, floor(random() * length(nums) + 1)::integer, 1) ||
    substr(chars, floor(random() * length(chars) + 1)::integer, 1) || 
    substr(nums, floor(random() * length(nums) + 1)::integer, 1);
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- Función alternativa manual por si necesitas forzar limpieza desde código
CREATE OR REPLACE FUNCTION delete_old_reports()
RETURNS void AS $$
BEGIN
  DELETE FROM public.reports WHERE created_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- ACTIVACIÓN DEL MOTOR EN TIEMPO REAL
-- ============================================
BEGIN;
  DROP PUBLICATION IF EXISTS supabase_realtime;
  CREATE PUBLICATION supabase_realtime;
COMMIT;

ALTER PUBLICATION supabase_realtime ADD TABLE reports;
ALTER PUBLICATION supabase_realtime ADD TABLE reactions;
ALTER PUBLICATION supabase_realtime ADD TABLE report_comments;
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;

-- ============================================================
-- FIN DE LA PARTE 1 (esquema base). Continúa la PARTE 2 abajo.
-- ============================================================
-- ============================================================
-- SafeZone — MIGRACIONES COMPLETAS (ejecutar TODO en una vez)
-- ============================================================
-- CÓMO USAR:
--   1. Entra a tu proyecto Supabase: https://supabase.com/dashboard
--   2. Menú izquierdo → "SQL Editor" → "New query"
--   3. Pega TODO este script y presiona "Run" (▶)
--
-- El script es SEGURO de repetir (usa IF NOT EXISTS / OR REPLACE).
-- Incluye: archivo de reportes, puntos vecinales, check-ins,
-- ranking, canjes premium, minijuegos y columnas premium.
-- ============================================================


-- ============================================================
-- 1) ARCHIVO AUTOMÁTICO DE REPORTES (migrations/archive_old_reports.sql)
-- ============================================================
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

CREATE INDEX IF NOT EXISTS idx_archived_reports_zone ON archived_reports(zone);
CREATE INDEX IF NOT EXISTS idx_archived_reports_category ON archived_reports(category);
CREATE INDEX IF NOT EXISTS idx_archived_reports_created_at ON archived_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_archived_reports_archived_at ON archived_reports(archived_at DESC);

ALTER TABLE archived_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Archived reports legible por cualquiera" ON archived_reports;
CREATE POLICY "Archived reports legible por cualquiera" ON archived_reports
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Archived reports insertable por cualquiera" ON archived_reports;
CREATE POLICY "Archived reports insertable por cualquiera" ON archived_reports
  FOR INSERT WITH CHECK (true);

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

DROP POLICY IF EXISTS "Archived reactions legible por cualquiera" ON archived_reactions;
CREATE POLICY "Archived reactions legible por cualquiera" ON archived_reactions
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Archived reactions insertable por cualquiera" ON archived_reactions;
CREATE POLICY "Archived reactions insertable por cualquiera" ON archived_reactions
  FOR INSERT WITH CHECK (true);

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
  INSERT INTO archived_reactions (id, report_id, user_code, reaction_type, created_at, archived_at)
  SELECT r.id, r.report_id, r.user_code, r.reaction_type, r.created_at, NOW()
  FROM reactions r
  INNER JOIN reports re ON re.id = r.report_id
  WHERE re.created_at < cutoff_date
  ON CONFLICT (id) DO NOTHING;

  DELETE FROM reactions r
  USING reports re
  WHERE re.id = r.report_id AND re.created_at < cutoff_date;

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

  DELETE FROM reports WHERE created_at < cutoff_date;

  RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2) PUNTOS VECINALES (migrations/vecino_points.sql)
-- ============================================================
CREATE TABLE IF NOT EXISTS community_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL,
  points INTEGER NOT NULL CHECK (points <> 0),
  reason TEXT NOT NULL CHECK (reason IN ('report', 'reaction', 'comment', 'sos', 'safe_checkin', 'redeem')),
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_points_user ON community_points(user_code);
CREATE INDEX IF NOT EXISTS idx_community_points_created ON community_points(created_at DESC);

ALTER TABLE community_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Points insertable por cualquiera" ON community_points;
CREATE POLICY "Points insertable por cualquiera" ON community_points
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Points legible por cualquiera" ON community_points;
CREATE POLICY "Points legible por cualquiera" ON community_points
  FOR SELECT USING (true);

CREATE OR REPLACE FUNCTION get_vecino_level(p_user_code TEXT)
RETURNS TABLE(total_points BIGINT, level TEXT, next_level_points BIGINT) AS $$
DECLARE
  v_total BIGINT;
BEGIN
  SELECT COALESCE(SUM(points), 0) INTO v_total
  FROM community_points
  WHERE user_code = p_user_code;

  RETURN QUERY
  SELECT
    v_total AS total_points,
    CASE
      WHEN v_total >= 100 THEN '🥇 Vigilante'
      WHEN v_total >= 50 THEN '🥈 Protector'
      WHEN v_total >= 20 THEN '🥉 Vecino Activo'
      WHEN v_total >= 5 THEN '🌱 Nuevo Vecino'
      ELSE '👤 Residente'
    END AS level,
    CASE
      WHEN v_total >= 100 THEN 0
      WHEN v_total >= 50 THEN 100 - v_total
      WHEN v_total >= 20 THEN 50 - v_total
      WHEN v_total >= 5 THEN 20 - v_total
      ELSE 5 - v_total
    END AS next_level_points;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_vecino_points(
  p_user_code TEXT,
  p_points INTEGER,
  p_reason TEXT,
  p_description TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
  v_total BIGINT;
BEGIN
  INSERT INTO community_points (user_code, points, reason, description)
  VALUES (p_user_code, p_points, p_reason, p_description);

  SELECT COALESCE(SUM(points), 0) INTO v_total
  FROM community_points
  WHERE user_code = p_user_code;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS safe_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL,
  zone INTEGER NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_safe_checkins_zone ON safe_checkins(zone);
CREATE INDEX IF NOT EXISTS idx_safe_checkins_created ON safe_checkins(created_at DESC);

ALTER TABLE safe_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Checkins insertable por cualquiera" ON safe_checkins;
CREATE POLICY "Checkins insertable por cualquiera" ON safe_checkins
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Checkins legible por cualquiera" ON safe_checkins;
CREATE POLICY "Checkins legible por cualquiera" ON safe_checkins
  FOR SELECT USING (true);

CREATE OR REPLACE FUNCTION do_safe_checkin(
  p_user_code TEXT,
  p_zone INTEGER,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_checkin_id UUID;
  v_total_points BIGINT;
  v_recent_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_recent_count
  FROM safe_checkins
  WHERE user_code = p_user_code
    AND created_at > NOW() - INTERVAL '30 minutes';

  IF v_recent_count > 0 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Ya hiciste check-in hace menos de 30 minutos'
    );
  END IF;

  INSERT INTO safe_checkins (user_code, zone, latitude, longitude)
  VALUES (p_user_code, p_zone, p_lat, p_lng)
  RETURNING id INTO v_checkin_id;

  INSERT INTO community_points (user_code, points, reason, description)
  VALUES (p_user_code, 3, 'safe_checkin', 'Check-in de zona segura');

  SELECT COALESCE(SUM(points), 0) INTO v_total_points
  FROM community_points
  WHERE user_code = p_user_code;

  RETURN json_build_object(
    'success', true,
    'checkin_id', v_checkin_id,
    'total_points', v_total_points,
    'message', '✅ Zona registrada como segura'
  );
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 3) RANKING Y CANJE (migrations/vecino_features.sql)
-- ============================================================
CREATE TABLE IF NOT EXISTS point_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL,
  points_spent INTEGER NOT NULL CHECK (points_spent > 0),
  days_premium INTEGER NOT NULL CHECK (days_premium > 0),
  redeemed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_redemptions_user ON point_redemptions(user_code);

ALTER TABLE point_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Redenciones insertable por cualquiera" ON point_redemptions;
CREATE POLICY "Redenciones insertable por cualquiera" ON point_redemptions
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Redenciones legible por cualquiera" ON point_redemptions;
CREATE POLICY "Redenciones legible por cualquiera" ON point_redemptions
  FOR SELECT USING (true);

CREATE OR REPLACE FUNCTION get_ranking(
  p_limit INTEGER DEFAULT 10
)
RETURNS TABLE(
  rank BIGINT,
  user_code TEXT,
  total_points BIGINT,
  level TEXT,
  report_count BIGINT,
  sos_count BIGINT,
  checkin_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(cp.points), 0) DESC)::BIGINT AS rank,
    cp.user_code,
    COALESCE(SUM(cp.points), 0) AS total_points,
    CASE
      WHEN COALESCE(SUM(cp.points), 0) >= 100 THEN '🥇 Vigilante'
      WHEN COALESCE(SUM(cp.points), 0) >= 50 THEN '🥈 Protector'
      WHEN COALESCE(SUM(cp.points), 0) >= 20 THEN '🥉 Vecino Activo'
      WHEN COALESCE(SUM(cp.points), 0) >= 5 THEN '🌱 Nuevo Vecino'
      ELSE '👤 Residente'
    END AS level,
    COALESCE((SELECT COUNT(*) FROM reports r WHERE r.user_code = cp.user_code), 0) AS report_count,
    COALESCE((SELECT COUNT(*) FROM sos_alerts s WHERE s.user_code = cp.user_code), 0) AS sos_count,
    COALESCE((SELECT COUNT(*) FROM safe_checkins sc WHERE sc.user_code = cp.user_code), 0) AS checkin_count
  FROM community_points cp
  GROUP BY cp.user_code
  ORDER BY total_points DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION redeem_points(
  p_user_code TEXT,
  p_points INTEGER
)
RETURNS JSON AS $$
DECLARE
  v_total BIGINT;
  v_days INTEGER;
  v_redemption_id UUID;
BEGIN
  SELECT COALESCE(SUM(points), 0) INTO v_total
  FROM community_points
  WHERE user_code = p_user_code;

  IF v_total < p_points THEN
    RETURN json_build_object(
      'success', false,
      'message', 'No tienes suficientes puntos. Necesitas ' || p_points || ' pts, tienes ' || v_total || ' pts.'
    );
  END IF;

  IF p_points < 50 OR p_points % 50 != 0 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Los puntos deben ser múltiplo de 50 (mínimo 50 pts = 1 día Premium).'
    );
  END IF;

  v_days := p_points / 50;

  INSERT INTO community_points (user_code, points, reason, description)
  VALUES (p_user_code, -p_points, 'redeem', 'Canjeó ' || p_points || ' pts por ' || v_days || ' días Premium')
  RETURNING id INTO v_redemption_id;

  INSERT INTO point_redemptions (user_code, points_spent, days_premium)
  VALUES (p_user_code, p_points, v_days);

  RETURN json_build_object(
    'success', true,
    'redemption_id', v_redemption_id,
    'days_premium', v_days,
    'points_spent', p_points,
    'message', '🎉 ¡Canje exitoso! ' || v_days || ' día(s) Premium añadido(s).'
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_redemptions(p_user_code TEXT)
RETURNS TABLE(
  id UUID,
  points_spent INTEGER,
  days_premium INTEGER,
  redeemed_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT pr.id, pr.points_spent, pr.days_premium, pr.redeemed_at
  FROM point_redemptions pr
  WHERE pr.user_code = p_user_code
  ORDER BY pr.redeemed_at DESC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 4) MINIJUEGOS (supabase_migration_games.sql)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code) ON DELETE CASCADE,
  game_type TEXT NOT NULL CHECK (game_type IN ('trivia', 'patrol')),
  score INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_scores_user_code ON user_scores(user_code);
CREATE INDEX IF NOT EXISTS idx_user_scores_game_type ON user_scores(game_type);
CREATE INDEX IF NOT EXISTS idx_user_scores_score ON user_scores(score DESC);
CREATE INDEX IF NOT EXISTS idx_user_scores_created_at ON user_scores(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_scores_user_game ON user_scores(user_code, game_type);

ALTER TABLE user_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_scores_insertable_by_own" ON user_scores;
CREATE POLICY "user_scores_insertable_by_own" ON user_scores
  FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "user_scores_readable_by_all" ON user_scores;
CREATE POLICY "user_scores_readable_by_all" ON user_scores
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "user_scores_updatable_by_own" ON user_scores;
CREATE POLICY "user_scores_updatable_by_own" ON user_scores
  FOR UPDATE
  USING (auth.uid() IS NULL OR user_code IN (
    SELECT user_code FROM profiles WHERE id = auth.uid()
  ));

CREATE OR REPLACE FUNCTION get_user_best_score(p_user_code TEXT, p_game_type TEXT)
RETURNS INTEGER AS $$
DECLARE
  best_score INTEGER;
BEGIN
  SELECT MAX(score) INTO best_score
  FROM user_scores
  WHERE user_code = p_user_code AND game_type = p_game_type;
  RETURN COALESCE(best_score, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_leaderboard(p_game_type TEXT, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (
  user_code TEXT,
  best_score INTEGER,
  last_played TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    us.user_code,
    MAX(us.score)::INTEGER AS best_score,
    MAX(us.created_at) AS last_played
  FROM user_scores us
  WHERE us.game_type = p_game_type
  GROUP BY us.user_code
  ORDER BY best_score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 5) COLUMNAS PREMIUM (supabase_migration_premium.sql)
-- ============================================================
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS premium_activated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_premium ON profiles(is_premium)
  WHERE is_premium = TRUE;

-- ============================================================
-- FIN — Todo aplicado correctamente si no ves errores rojos.
-- ============================================================


-- ============================================================
-- 6) MERCADO PAGO — SUSCRIPCIONES PREMIUM
-- ============================================================
-- Guarda el ID de la suscripción de Mercado Pago para poder
-- verificar su estado y desactivar Premium si se cancela.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS mercadopago_subscription_id TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_mp_subscription
  ON profiles(mercadopago_subscription_id)
  WHERE mercadopago_subscription_id IS NOT NULL;

-- ============================================================
-- PRUEBA FINAL: debe devolver 0 (o el número de reportes archivados)
-- Si ves un error rojo, avísame qué dice.
-- ============================================================
SELECT archive_old_reports() AS prueba_rapida;


-- Recarga la caché de Supabase para que la app vea las funciones nuevas
NOTIFY pgrst, 'reload schema';
