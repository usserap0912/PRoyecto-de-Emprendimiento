-- ============================================
-- SafeZone - Esquema de Base de Datos Supabase
-- Collique, Comas - Red Vecinal de Seguridad
-- ============================================

-- 1. Tabla de Perfiles (usuarios anónimos)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT UNIQUE NOT NULL,
  zone INTEGER NOT NULL CHECK (zone >= 1 AND zone <= 7),
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
  category TEXT NOT NULL CHECK (category IN ('robo', 'sospechoso', 'extorsion', 'alumbrado', 'otros')),
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
  check_count INTEGER DEFAULT 0
);

-- Índices para reportes
CREATE INDEX IF NOT EXISTS idx_reports_zone ON reports(zone);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_tag ON reports(tag);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON reports(created_at DESC);

-- 3. Tabla de Reacciones
CREATE TABLE IF NOT EXISTS reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  reaction_type TEXT NOT NULL CHECK (reaction_type IN ('shield', 'alert', 'check')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(report_id, user_code, reaction_type)
);

CREATE INDEX IF NOT EXISTS idx_reactions_report_id ON reactions(report_id);

-- 4. Tabla de Mensajes del Chat
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at ASC);

-- 5. Tabla de Alertas S.O.S.
CREATE TABLE IF NOT EXISTS sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_code TEXT NOT NULL REFERENCES profiles(user_code),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  status TEXT DEFAULT 'activo' CHECK (status IN ('activo', 'cancelado', 'atendido')),
  created_at TIMESTAMPTZ DEFAULT NOW()
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
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;

-- Políticas: cualquier usuario autenticado puede leer/escribir
-- (en SafeZone la autenticación es anónima por diseño)

CREATE POLICY "Profiles insertable por cualquiera" ON profiles
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Profiles legibles por cualquiera" ON profiles
  FOR SELECT USING (true);

CREATE POLICY "Reports insertable por cualquiera" ON reports
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Reports legibles por cualquiera" ON reports
  FOR SELECT USING (true);

CREATE POLICY "Reports actualizable por cualquiera" ON reports
  FOR UPDATE USING (true);

CREATE POLICY "Reactions insertable por cualquiera" ON reactions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Reactions legible por cualquiera" ON reactions
  FOR SELECT USING (true);

CREATE POLICY "Chat messages insertable por cualquiera" ON chat_messages
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Chat messages legible por cualquiera" ON chat_messages
  FOR SELECT USING (true);

CREATE POLICY "SOS alerts insertable por cualquiera" ON sos_alerts
  FOR INSERT WITH CHECK (true);

CREATE POLICY "SOS alerts legible por cualquiera" ON sos_alerts
  FOR SELECT USING (true);

CREATE POLICY "SOS alerts actualizable por cualquiera" ON sos_alerts
  FOR UPDATE USING (true);

-- ============================================
-- FUNCIÓN: Actualizar contadores de reacciones
-- ============================================

CREATE OR REPLACE FUNCTION update_report_reaction_counts()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE reports
  SET
    shield_count = (SELECT COUNT(*) FROM reactions WHERE report_id = NEW.report_id AND reaction_type = 'shield'),
    alert_count = (SELECT COUNT(*) FROM reactions WHERE report_id = NEW.report_id AND reaction_type = 'alert'),
    check_count = (SELECT COUNT(*) FROM reactions WHERE report_id = NEW.report_id AND reaction_type = 'check')
  WHERE id = NEW.report_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_reaction_counts
  AFTER INSERT OR DELETE ON reactions
  FOR EACH ROW
  EXECUTE FUNCTION update_report_reaction_counts();

-- ============================================
-- FUNCIÓN: Generar código de usuario único
-- ============================================

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
