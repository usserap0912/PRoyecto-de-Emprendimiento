-- SafeZone - Anonymous Auth, identidad pseudonima y RLS progresiva.
-- Revisar y ejecutar manualmente. No ejecutar sql_completo.sql despues.
-- Requiere habilitar Anonymous Sign-Ins en Supabase Auth.

BEGIN;

-- Las filas heredadas permanecen con auth_user_id NULL hasta que un proceso
-- administrativo pueda verificar su propiedad. Nunca se reclaman solo por
-- presentar el user_code visible.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.report_comments
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.reactions
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.sos_alerts
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.community_points
  ADD COLUMN IF NOT EXISTS auth_user_id UUID,
  ADD COLUMN IF NOT EXISTS source_id UUID;
ALTER TABLE public.safe_checkins
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.user_scores
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.point_redemptions
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;

DO $$
DECLARE
  target_table TEXT;
  constraint_name TEXT;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'profiles',
    'reports',
    'report_comments',
    'reactions',
    'sos_alerts',
    'chat_messages',
    'community_points',
    'safe_checkins',
    'user_scores',
    'point_redemptions'
  ]
  LOOP
    constraint_name := target_table || '_auth_user_id_fkey';
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint
      WHERE conname = constraint_name
        AND conrelid = ('public.' || target_table)::regclass
    ) THEN
      EXECUTE pg_catalog.format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I '
        'FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL',
        target_table,
        constraint_name
      );
    END IF;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_auth_user_id_unique
  ON public.profiles(auth_user_id)
  WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS reports_auth_user_id_idx
  ON public.reports(auth_user_id);
CREATE INDEX IF NOT EXISTS report_comments_auth_user_id_idx
  ON public.report_comments(auth_user_id);
CREATE INDEX IF NOT EXISTS reactions_auth_user_id_idx
  ON public.reactions(auth_user_id);
CREATE INDEX IF NOT EXISTS sos_alerts_auth_user_id_idx
  ON public.sos_alerts(auth_user_id);
CREATE INDEX IF NOT EXISTS chat_messages_auth_user_id_idx
  ON public.chat_messages(auth_user_id);
CREATE INDEX IF NOT EXISTS community_points_auth_user_id_idx
  ON public.community_points(auth_user_id);
CREATE INDEX IF NOT EXISTS safe_checkins_auth_user_id_idx
  ON public.safe_checkins(auth_user_id);
CREATE INDEX IF NOT EXISTS user_scores_auth_user_id_idx
  ON public.user_scores(auth_user_id);
CREATE INDEX IF NOT EXISTS point_redemptions_auth_user_id_idx
  ON public.point_redemptions(auth_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS community_points_once_per_source
  ON public.community_points(auth_user_id, reason, source_id)
  WHERE auth_user_id IS NOT NULL AND source_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.legacy_identity_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_user_code TEXT NOT NULL REFERENCES public.profiles(user_code),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);
ALTER TABLE public.legacy_identity_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Legacy claims legibles por propietario"
  ON public.legacy_identity_claims;
CREATE POLICY "Legacy claims legibles por propietario"
  ON public.legacy_identity_claims FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

-- Devuelve el perfil de la sesion. El cliente nunca selecciona la identidad.
CREATE OR REPLACE FUNCTION public.get_current_identity(
  p_legacy_user_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  linked_profile public.profiles%ROWTYPE;
  legacy_profile public.profiles%ROWTYPE;
BEGIN
  IF current_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO linked_profile
  FROM public.profiles
  WHERE auth_user_id = current_auth_user_id;

  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'status', 'linked',
      'auth_user_id', linked_profile.auth_user_id,
      'user_code', linked_profile.user_code,
      'zone', linked_profile.zone
    );
  END IF;

  IF p_legacy_user_code IS NOT NULL AND pg_catalog.btrim(p_legacy_user_code) <> '' THEN
    SELECT * INTO legacy_profile
    FROM public.profiles
    WHERE user_code = pg_catalog.btrim(p_legacy_user_code);

    IF FOUND AND legacy_profile.auth_user_id IS NULL THEN
      INSERT INTO public.legacy_identity_claims (
        auth_user_id, requested_user_code, status, requested_at
      ) VALUES (
        current_auth_user_id, legacy_profile.user_code, 'pending', NOW()
      )
      ON CONFLICT (auth_user_id) DO UPDATE SET
        requested_user_code = EXCLUDED.requested_user_code,
        status = 'pending',
        requested_at = NOW(),
        reviewed_at = NULL;
      RETURN pg_catalog.jsonb_build_object(
        'status', 'legacy_unverified',
        'user_code', legacy_profile.user_code,
        'zone', legacy_profile.zone
      );
    END IF;

    IF FOUND THEN
      RETURN pg_catalog.jsonb_build_object('status', 'legacy_conflict');
    END IF;
  END IF;

  RETURN pg_catalog.jsonb_build_object('status', 'needs_profile');
END;
$$;

-- Crea solamente el perfil de auth.uid(). Un codigo legado existente nunca se
-- reclama automaticamente; un codigo local sin fila remota si puede conservarse.
CREATE OR REPLACE FUNCTION public.create_current_profile(
  p_zone INTEGER,
  p_preferred_user_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  existing_profile public.profiles%ROWTYPE;
  candidate_code TEXT;
  attempt INTEGER := 0;
BEGIN
  IF current_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  -- El selector actual reconoce I-X. VII-X son zonas seleccionables sin
  -- convertirlas en puntos, centroides o limites territoriales verificados.
  IF p_zone < 1 OR p_zone > 10 THEN
    RAISE EXCEPTION 'invalid selectable zone' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_auth_user_id::TEXT, 0)
  );

  SELECT * INTO existing_profile
  FROM public.profiles
  WHERE auth_user_id = current_auth_user_id;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'status', 'linked',
      'auth_user_id', existing_profile.auth_user_id,
      'user_code', existing_profile.user_code,
      'zone', existing_profile.zone
    );
  END IF;

  IF p_preferred_user_code IS NOT NULL
      AND pg_catalog.btrim(p_preferred_user_code) <> '' THEN
    candidate_code := pg_catalog.btrim(p_preferred_user_code);
    IF candidate_code !~ '^User-[A-Z0-9]{4,12}$' THEN
      RAISE EXCEPTION 'invalid preferred user code' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.profiles WHERE user_code = candidate_code
    ) THEN
      RAISE EXCEPTION 'legacy profile requires verification'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  LOOP
    attempt := attempt + 1;
    IF candidate_code IS NULL THEN
      candidate_code := 'User-' || pg_catalog.upper(
        pg_catalog.substr(
          pg_catalog.replace(pg_catalog.gen_random_uuid()::TEXT, '-', ''),
          1,
          6
        )
      );
    END IF;

    BEGIN
      INSERT INTO public.profiles (auth_user_id, user_code, zone)
      VALUES (current_auth_user_id, candidate_code, p_zone)
      RETURNING * INTO existing_profile;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF p_preferred_user_code IS NOT NULL OR attempt >= 20 THEN
        RAISE;
      END IF;
      candidate_code := NULL;
    END;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'status', 'created',
    'auth_user_id', existing_profile.auth_user_id,
    'user_code', existing_profile.user_code,
    'zone', existing_profile.zone
  );
END;
$$;

-- Ignora user_code/auth_user_id suministrados por Flutter y los deriva del JWT.
CREATE OR REPLACE FUNCTION public.assign_current_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  current_user_code TEXT;
BEGIN
  IF current_auth_user_id IS NULL THEN
    -- El enlace legado lo ejecuta un administrador/service_role y el trigger
    -- backfill_linked_profile_identity propaga solamente auth_user_id sobre
    -- filas del mismo alias. Las politicas RLS impiden este UPDATE a clientes.
    IF TG_OP = 'UPDATE'
        AND OLD.auth_user_id IS NULL
        AND NEW.auth_user_id IS NOT NULL
        AND NEW.user_code IS NOT DISTINCT FROM OLD.user_code THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT user_code INTO current_user_code
  FROM public.profiles
  WHERE auth_user_id = current_auth_user_id;
  IF current_user_code IS NULL THEN
    RAISE EXCEPTION 'linked profile required' USING ERRCODE = '42501';
  END IF;
  NEW.auth_user_id := current_auth_user_id;
  NEW.user_code := current_user_code;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  target_table TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'reports',
    'report_comments',
    'reactions',
    'sos_alerts',
    'chat_messages',
    'community_points',
    'safe_checkins',
    'user_scores',
    'point_redemptions'
  ]
  LOOP
    trigger_name := 'set_' || target_table || '_identity';
    EXECUTE pg_catalog.format(
      'DROP TRIGGER IF EXISTS %I ON public.%I',
      trigger_name,
      target_table
    );
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.assign_current_identity()',
      trigger_name,
      target_table
    );
  END LOOP;
END;
$$;

-- Un enlace legado realizado por un administrador propaga la identidad a todo
-- el historial sin cambiar user_code ni claves foraneas existentes.
CREATE OR REPLACE FUNCTION public.backfill_linked_profile_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.auth_user_id IS NULL AND NEW.auth_user_id IS NOT NULL THEN
    UPDATE public.reports SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.report_comments SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.reactions SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.sos_alerts SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.chat_messages SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.community_points SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.safe_checkins SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.user_scores SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.point_redemptions SET auth_user_id = NEW.auth_user_id
      WHERE user_code = NEW.user_code AND auth_user_id IS NULL;
    UPDATE public.legacy_identity_claims
    SET status = 'approved', reviewed_at = NOW()
    WHERE auth_user_id = NEW.auth_user_id
      AND requested_user_code = NEW.user_code;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS backfill_profile_identity ON public.profiles;
CREATE TRIGGER backfill_profile_identity
  AFTER UPDATE OF auth_user_id ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.backfill_linked_profile_identity();

-- RLS principal. Los datos publicos del Muro conservan lectura para sesiones
-- autenticadas anonimamente; todas las escrituras verifican auth.uid().
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Profiles insertable por cualquiera" ON public.profiles;
DROP POLICY IF EXISTS "Profiles legibles por cualquiera" ON public.profiles;
DROP POLICY IF EXISTS "Profiles legibles por propietario" ON public.profiles;
DROP POLICY IF EXISTS "Profiles actualizables por propietario" ON public.profiles;
CREATE POLICY "Profiles legibles por propietario" ON public.profiles
  FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.update_current_profile_zone(p_zone INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_zone < 1 OR p_zone > 10 THEN
    RAISE EXCEPTION 'invalid selectable zone' USING ERRCODE = '22023';
  END IF;
  UPDATE public.profiles
  SET zone = p_zone
  WHERE auth_user_id = (SELECT auth.uid());
  IF NOT FOUND THEN
    RAISE EXCEPTION 'linked profile required' USING ERRCODE = '42501';
  END IF;
END;
$$;

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Reports insertable por cualquiera" ON public.reports;
DROP POLICY IF EXISTS "Reports legibles por cualquiera" ON public.reports;
DROP POLICY IF EXISTS "Reports actualizable por cualquiera" ON public.reports;
DROP POLICY IF EXISTS "Reports legibles por usuarios" ON public.reports;
DROP POLICY IF EXISTS "Reports insertables por propietario" ON public.reports;
DROP POLICY IF EXISTS "Reports actualizables por propietario" ON public.reports;
CREATE POLICY "Reports legibles por usuarios" ON public.reports
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Reports insertables por propietario" ON public.reports
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = (SELECT auth.uid()));
CREATE POLICY "Reports actualizables por propietario" ON public.reports
  FOR UPDATE TO authenticated
  USING (auth_user_id = (SELECT auth.uid()))
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.report_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Comments insertable por cualquiera" ON public.report_comments;
DROP POLICY IF EXISTS "Comments legible por cualquiera" ON public.report_comments;
DROP POLICY IF EXISTS "Comments legibles por usuarios" ON public.report_comments;
DROP POLICY IF EXISTS "Comments insertables por propietario" ON public.report_comments;
CREATE POLICY "Comments legibles por usuarios" ON public.report_comments
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Comments insertables por propietario" ON public.report_comments
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Reactions insertable por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions legible por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions eliminable por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions actualizable por cualquiera" ON public.reactions;
DROP POLICY IF EXISTS "Reactions legibles por usuarios" ON public.reactions;
CREATE POLICY "Reactions legibles por usuarios" ON public.reactions
  FOR SELECT TO authenticated USING (true);

ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SOS alerts insertable por cualquiera" ON public.sos_alerts;
DROP POLICY IF EXISTS "SOS alerts legible por cualquiera" ON public.sos_alerts;
DROP POLICY IF EXISTS "SOS alerts actualizable por cualquiera" ON public.sos_alerts;
DROP POLICY IF EXISTS "SOS legibles por usuarios" ON public.sos_alerts;
DROP POLICY IF EXISTS "SOS insertables por propietario" ON public.sos_alerts;
DROP POLICY IF EXISTS "SOS actualizables por propietario" ON public.sos_alerts;
CREATE POLICY "SOS legibles por usuarios" ON public.sos_alerts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "SOS insertables por propietario" ON public.sos_alerts
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = (SELECT auth.uid()));
CREATE POLICY "SOS actualizables por propietario" ON public.sos_alerts
  FOR UPDATE TO authenticated
  USING (auth_user_id = (SELECT auth.uid()))
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Chat messages insertable por cualquiera" ON public.chat_messages;
DROP POLICY IF EXISTS "Chat messages legible por cualquiera" ON public.chat_messages;
DROP POLICY IF EXISTS "Chat legible por usuarios" ON public.chat_messages;
DROP POLICY IF EXISTS "Chat insertable por propietario" ON public.chat_messages;
CREATE POLICY "Chat legible por usuarios" ON public.chat_messages
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Chat insertable por propietario" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.community_points ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Points insertable por cualquiera" ON public.community_points;
DROP POLICY IF EXISTS "Points legible por cualquiera" ON public.community_points;
DROP POLICY IF EXISTS "Points legibles por propietario" ON public.community_points;
CREATE POLICY "Points legibles por propietario" ON public.community_points
  FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.safe_checkins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Checkins insertable por cualquiera" ON public.safe_checkins;
DROP POLICY IF EXISTS "Checkins legible por cualquiera" ON public.safe_checkins;
DROP POLICY IF EXISTS "Checkins legibles por propietario" ON public.safe_checkins;
CREATE POLICY "Checkins legibles por propietario" ON public.safe_checkins
  FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.point_redemptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Redenciones insertable por cualquiera" ON public.point_redemptions;
DROP POLICY IF EXISTS "Redenciones legible por cualquiera" ON public.point_redemptions;
DROP POLICY IF EXISTS "Redenciones legibles por propietario" ON public.point_redemptions;
CREATE POLICY "Redenciones legibles por propietario" ON public.point_redemptions
  FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

ALTER TABLE public.user_scores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_scores_insertable_by_own" ON public.user_scores;
DROP POLICY IF EXISTS "user_scores_readable_by_all" ON public.user_scores;
DROP POLICY IF EXISTS "user_scores_updatable_by_own" ON public.user_scores;
DROP POLICY IF EXISTS "Scores legibles por usuarios" ON public.user_scores;
DROP POLICY IF EXISTS "Scores insertables por propietario" ON public.user_scores;
DROP POLICY IF EXISTS "Scores actualizables por propietario" ON public.user_scores;
CREATE POLICY "Scores legibles por usuarios" ON public.user_scores
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Scores insertables por propietario" ON public.user_scores
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = (SELECT auth.uid()));
CREATE POLICY "Scores actualizables por propietario" ON public.user_scores
  FOR UPDATE TO authenticated
  USING (auth_user_id = (SELECT auth.uid()))
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

-- Puntos por reportar y reaccionar se conceden desde triggers, una sola vez por
-- fuente. El cliente deja de poder autootorgarse puntos con add_vecino_points.
CREATE OR REPLACE FUNCTION public.award_report_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL AND NEW.category <> 'sos' THEN
    INSERT INTO public.community_points (
      auth_user_id, user_code, points, reason, description, source_id
    ) VALUES (
      NEW.auth_user_id, NEW.user_code, 10, 'report',
      'Reporto un incidente', NEW.id
    ) ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS award_points_after_report ON public.reports;
CREATE TRIGGER award_points_after_report
  AFTER INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.award_report_points();

CREATE OR REPLACE FUNCTION public.award_reaction_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL THEN
    INSERT INTO public.community_points (
      auth_user_id, user_code, points, reason, description, source_id
    ) VALUES (
      NEW.auth_user_id, NEW.user_code, 5, 'reaction',
      'Reacciono a un reporte', NEW.report_id
    ) ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS award_points_after_reaction ON public.reactions;
CREATE TRIGGER award_points_after_reaction
  AFTER INSERT ON public.reactions
  FOR EACH ROW EXECUTE FUNCTION public.award_reaction_points();

CREATE OR REPLACE FUNCTION public.get_current_vecino_level()
RETURNS TABLE(total_points BIGINT, level TEXT, next_level_points BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  total BIGINT;
BEGIN
  IF current_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT pg_catalog.coalesce(pg_catalog.sum(points), 0) INTO total
  FROM public.community_points
  WHERE auth_user_id = current_auth_user_id;
  RETURN QUERY SELECT
    total,
    CASE
      WHEN total >= 100 THEN '🥇 Vigilante'
      WHEN total >= 50 THEN '🥈 Protector'
      WHEN total >= 20 THEN '🥉 Vecino Activo'
      WHEN total >= 5 THEN '🌱 Nuevo Vecino'
      ELSE '👤 Residente'
    END,
    CASE
      WHEN total >= 100 THEN 0
      WHEN total >= 50 THEN 100 - total
      WHEN total >= 20 THEN 50 - total
      WHEN total >= 5 THEN 20 - total
      ELSE 5 - total
    END;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ranking(p_limit INTEGER DEFAULT 10)
RETURNS TABLE(
  rank BIGINT,
  user_code TEXT,
  total_points BIGINT,
  level TEXT,
  report_count BIGINT,
  sos_count BIGINT,
  checkin_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH totals AS (
    SELECT cp.user_code, pg_catalog.coalesce(pg_catalog.sum(cp.points), 0) AS total
    FROM public.community_points cp
    GROUP BY cp.user_code
  )
  SELECT
    pg_catalog.row_number() OVER (ORDER BY t.total DESC),
    t.user_code,
    t.total,
    CASE
      WHEN t.total >= 100 THEN '🥇 Vigilante'
      WHEN t.total >= 50 THEN '🥈 Protector'
      WHEN t.total >= 20 THEN '🥉 Vecino Activo'
      WHEN t.total >= 5 THEN '🌱 Nuevo Vecino'
      ELSE '👤 Residente'
    END,
    (SELECT pg_catalog.count(*) FROM public.reports r
      WHERE r.user_code = t.user_code),
    (SELECT pg_catalog.count(*) FROM public.sos_alerts s
      WHERE s.user_code = t.user_code),
    (SELECT pg_catalog.count(*) FROM public.safe_checkins sc
      WHERE sc.user_code = t.user_code)
  FROM totals t
  ORDER BY t.total DESC
  LIMIT pg_catalog.greatest(1, pg_catalog.least(p_limit, 100))
$$;

CREATE OR REPLACE FUNCTION public.do_current_safe_checkin(
  p_zone INTEGER,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  current_user_code TEXT;
  checkin_id UUID;
  total BIGINT;
BEGIN
  SELECT user_code INTO current_user_code FROM public.profiles
    WHERE auth_user_id = current_auth_user_id;
  IF current_user_code IS NULL THEN
    RAISE EXCEPTION 'linked profile required' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.safe_checkins
    WHERE auth_user_id = current_auth_user_id
      AND created_at > pg_catalog.now() - INTERVAL '30 minutes'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'message', 'Ya hiciste check-in hace menos de 30 minutos'
    );
  END IF;
  INSERT INTO public.safe_checkins (
    auth_user_id, user_code, zone, latitude, longitude
  ) VALUES (
    current_auth_user_id, current_user_code, p_zone, p_lat, p_lng
  ) RETURNING id INTO checkin_id;
  INSERT INTO public.community_points (
    auth_user_id, user_code, points, reason, description, source_id
  ) VALUES (
    current_auth_user_id, current_user_code, 3, 'safe_checkin',
    'Check-in de zona segura', checkin_id
  ) ON CONFLICT DO NOTHING;
  SELECT pg_catalog.coalesce(pg_catalog.sum(points), 0) INTO total
  FROM public.community_points WHERE auth_user_id = current_auth_user_id;
  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'checkin_id', checkin_id,
    'total_points', total,
    'message', '✅ Zona registrada como segura'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.redeem_current_user_points(p_points INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_auth_user_id UUID := (SELECT auth.uid());
  current_user_code TEXT;
  total BIGINT;
  days INTEGER;
  redemption_id UUID;
BEGIN
  SELECT user_code INTO current_user_code FROM public.profiles
    WHERE auth_user_id = current_auth_user_id;
  IF current_user_code IS NULL THEN
    RAISE EXCEPTION 'linked profile required' USING ERRCODE = '42501';
  END IF;
  IF p_points < 50 OR p_points % 50 <> 0 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'message', 'Los puntos deben ser multiplo de 50.'
    );
  END IF;
  SELECT pg_catalog.coalesce(pg_catalog.sum(points), 0) INTO total
  FROM public.community_points WHERE auth_user_id = current_auth_user_id;
  IF total < p_points THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'message', 'No tienes suficientes puntos.'
    );
  END IF;
  days := p_points / 50;
  INSERT INTO public.community_points (
    auth_user_id, user_code, points, reason, description
  ) VALUES (
    current_auth_user_id, current_user_code, -p_points, 'redeem',
    'Canje de puntos por Premium'
  ) RETURNING id INTO redemption_id;
  INSERT INTO public.point_redemptions (
    auth_user_id, user_code, points_spent, days_premium
  ) VALUES (
    current_auth_user_id, current_user_code, p_points, days
  );
  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'redemption_id', redemption_id,
    'days_premium', days,
    'points_spent', p_points,
    'message', '🎉 Canje exitoso'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_current_redemptions()
RETURNS TABLE(
  id UUID,
  points_spent INTEGER,
  days_premium INTEGER,
  redeemed_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pr.id, pr.points_spent, pr.days_premium, pr.redeemed_at
  FROM public.point_redemptions pr
  WHERE pr.auth_user_id = (SELECT auth.uid())
  ORDER BY pr.redeemed_at DESC
  LIMIT 20
$$;

-- Las RPC heredadas que aceptan identidad o permiten autootorgar puntos dejan
-- de estar expuestas. Sus reemplazos derivan auth.uid().
DO $$
BEGIN
  IF pg_catalog.to_regprocedure(
    'public.add_vecino_points(text,integer,text,text)'
  ) IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.add_vecino_points(TEXT, INTEGER, TEXT, TEXT)
      FROM PUBLIC, anon, authenticated;
  END IF;
  IF pg_catalog.to_regprocedure(
    'public.do_safe_checkin(text,integer,double precision,double precision)'
  ) IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.do_safe_checkin(
      TEXT, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION
    ) FROM PUBLIC, anon, authenticated;
  END IF;
  IF pg_catalog.to_regprocedure(
    'public.redeem_points(text,integer)'
  ) IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.redeem_points(TEXT, INTEGER)
      FROM PUBLIC, anon, authenticated;
  END IF;
  IF pg_catalog.to_regprocedure(
    'public.get_redemptions(text)'
  ) IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.get_redemptions(TEXT)
      FROM PUBLIC, anon, authenticated;
  END IF;
  IF pg_catalog.to_regprocedure(
    'public.get_vecino_level(text)'
  ) IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.get_vecino_level(TEXT)
      FROM PUBLIC, anon, authenticated;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_current_identity(TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_current_profile(INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_current_vecino_level()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.do_current_safe_checkin(INTEGER, DOUBLE PRECISION, DOUBLE PRECISION)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.redeem_current_user_points(INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_current_redemptions()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_current_profile_zone(INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_ranking(INTEGER)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_current_identity(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_current_profile(INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_vecino_level() TO authenticated;
GRANT EXECUTE ON FUNCTION public.do_current_safe_checkin(INTEGER, DOUBLE PRECISION, DOUBLE PRECISION)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_current_user_points(INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_redemptions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_current_profile_zone(INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ranking(INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.assign_current_identity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_linked_profile_identity()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.award_report_points() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.award_reaction_points() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
