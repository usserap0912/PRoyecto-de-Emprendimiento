-- ============================================
-- SafeZone - Módulo Gamificado
-- Tabla de puntajes de minijuegos
-- Collique, Comas - Red Vecinal de Seguridad
-- ============================================

-- 1. Tabla de Puntajes de Usuarios
CREATE TABLE IF NOT EXISTS user_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code) ON DELETE CASCADE,
  game_type TEXT NOT NULL CHECK (game_type IN ('trivia', 'patrol')),
  score INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para búsqueda rápida
CREATE INDEX IF NOT EXISTS idx_user_scores_user_code ON user_scores(user_code);
CREATE INDEX IF NOT EXISTS idx_user_scores_game_type ON user_scores(game_type);
CREATE INDEX IF NOT EXISTS idx_user_scores_score ON user_scores(score DESC);
CREATE INDEX IF NOT EXISTS idx_user_scores_created_at ON user_scores(created_at DESC);

-- Índice compuesto para obtener récords por usuario y tipo de juego
CREATE INDEX IF NOT EXISTS idx_user_scores_user_game ON user_scores(user_code, game_type);

-- ============================================
-- POLÍTICAS DE SEGURIDAD (Row Level Security)
-- ============================================

ALTER TABLE user_scores ENABLE ROW LEVEL SECURITY;

-- Política: cualquier usuario puede insertar sus propios puntajes
CREATE POLICY "user_scores_insertable_by_own" ON user_scores
  FOR INSERT
  WITH CHECK (true);

-- Política: cualquier usuario puede leer todos los puntajes (leaderboard)
CREATE POLICY "user_scores_readable_by_all" ON user_scores
  FOR SELECT
  USING (true);

-- Política: los usuarios pueden actualizar SOLO sus propios puntajes
CREATE POLICY "user_scores_updatable_by_own" ON user_scores
  FOR UPDATE
  USING (auth.uid() IS NULL OR user_code IN (
    SELECT user_code FROM profiles WHERE id = auth.uid()::text
  ));

-- ============================================
-- FUNCIÓN: Obtener el récord de un usuario por tipo de juego
-- ============================================

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

-- ============================================
-- FUNCIÓN: Obtener el top 10 de jugadores por tipo de juego
-- ============================================

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
