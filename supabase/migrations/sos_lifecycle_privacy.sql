-- SafeZone SOS lifecycle and privacy migration.
-- Apply once in Supabase before enabling the new production SOS flow.

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_category_check;
ALTER TABLE reports
  ADD CONSTRAINT reports_category_check
  CHECK (category IN (
    'robo', 'sos', 'sospechoso', 'extorsion', 'alumbrado', 'otros'
  ));

-- Coordinates are required only while an alert is active. Once it finishes,
-- the audit record retains actor, timestamps and status but no public location.
ALTER TABLE sos_alerts ALTER COLUMN latitude DROP NOT NULL;
ALTER TABLE sos_alerts ALTER COLUMN longitude DROP NOT NULL;
ALTER TABLE sos_alerts
  ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;

-- Realtime must be enabled for online recipients. The duplicate-object guard
-- keeps the migration idempotent on projects where these tables were enabled.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_alerts;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE reports;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
