-- RFC-0005 delegated sync doorbells and the Android FCM transport.
-- Existing rows are Direct CLI pairings delivered over APNs.

ALTER TABLE wake_registrations ADD COLUMN platform TEXT NOT NULL DEFAULT 'apns';  -- 'apns' | 'fcm'
ALTER TABLE wake_registrations ADD COLUMN purpose TEXT NOT NULL DEFAULT 'direct-cli'; -- 'direct-cli' | 'delegated-sync'
