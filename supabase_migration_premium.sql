-- ============================================
-- SafeZone - Esquema de Suscripción Premium
-- ============================================
-- Agrega las columnas necesarias para el
-- sistema de suscripción premium a la tabla profiles.
-- ============================================

-- Agregar columnas a la tabla profiles
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS premium_activated_at TIMESTAMPTZ;

-- Index para búsqueda rápida por stripe_customer_id
CREATE INDEX IF NOT EXISTS idx_profiles_stripe_customer ON profiles(stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

-- Index para filtrar usuarios premium
CREATE INDEX IF NOT EXISTS idx_profiles_premium ON profiles(is_premium)
  WHERE is_premium = TRUE;
