-- ============================================
-- SafeZone - Ranking Vecinal y Canje de Puntos
-- ============================================

-- 1. Tabla de canjes de puntos (redenciones)
CREATE TABLE IF NOT EXISTS point_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL,
  points_spent INTEGER NOT NULL CHECK (points_spent > 0),
  days_premium INTEGER NOT NULL CHECK (days_premium > 0),
  redeemed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_redemptions_user ON point_redemptions(user_code);

ALTER TABLE point_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Redenciones insertable por cualquiera" ON point_redemptions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Redenciones legible por cualquiera" ON point_redemptions
  FOR SELECT USING (true);

-- 2. Función: Obtener ranking de vecinos por puntos (top N)
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

-- 3. Función: Canjear puntos por días Premium
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
  -- Validar puntos disponibles
  SELECT COALESCE(SUM(points), 0) INTO v_total
  FROM community_points
  WHERE user_code = p_user_code;

  IF v_total < p_points THEN
    RETURN json_build_object(
      'success', false,
      'message', 'No tienes suficientes puntos. Necesitas ' || p_points || ' pts, tienes ' || v_total || ' pts.'
    );
  END IF;

  -- Validar que los puntos sean un monto válido (múltiplo de 50)
  IF p_points < 50 OR p_points % 50 != 0 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Los puntos deben ser múltiplo de 50 (mínimo 50 pts = 1 día Premium).'
    );
  END IF;

  -- Calcular días Premium (50 pts = 1 día)
  v_days := p_points / 50;

  -- Registrar redención (puntos negativos)
  INSERT INTO community_points (user_code, points, reason, description)
  VALUES (p_user_code, -p_points, 'redeem', 'Canjeó ' || p_points || ' pts por ' || v_days || ' días Premium')
  RETURNING id INTO v_redemption_id;

  -- Registrar en tabla de redenciones
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

-- 4. Función: Verificar historial de canjes de un usuario
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
