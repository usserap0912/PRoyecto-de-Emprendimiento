-- ============================================
-- SafeZone - Sistema de Puntos Vecinal
-- ============================================

-- 1. Tabla de Puntos de la Comunidad
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

CREATE POLICY "Points insertable por cualquiera" ON community_points
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Points legible por cualquiera" ON community_points
  FOR SELECT USING (true);

-- 2. Función: Obtener nivel de vecino
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

-- 3. Función: Agregar puntos a un vecino
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

-- 4. Tabla de Check-ins de Zona Segura
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

CREATE POLICY "Checkins insertable por cualquiera" ON safe_checkins
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Checkins legible por cualquiera" ON safe_checkins
  FOR SELECT USING (true);

-- 5. Función: Hacer check-in de zona segura
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
  -- Verificar que no haya hecho check-in en los últimos 30 min
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

  -- Insertar check-in
  INSERT INTO safe_checkins (user_code, zone, latitude, longitude)
  VALUES (p_user_code, p_zone, p_lat, p_lng)
  RETURNING id INTO v_checkin_id;

  -- Otorgar puntos por check-in
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
