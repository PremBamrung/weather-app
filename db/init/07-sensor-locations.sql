-- Sensor -> room binding (see docs/grafana-floorplan-heatmap.md, "Prerequisite for every
-- option: bind channel -> room"; also closes docs/grafana-review.md §5's channel-naming item).
--
-- Nothing in the schema knew that WN31 channel 1 is the main bedroom. `sensor_channels` is
-- keyed by (sensor_type, channel), so every panel could only ever say "Room 1". This adds the
-- dimension table that names them, and the `room_readings` view that joins it in.
--
-- Rows are TIME-RANGED, not current-state. Sensors move: WN31 ch2 is in the desk room today
-- and is planned for the living room, and the WS69 array is indoors in the living room until
-- it goes on the roof. A current-location-only table would retroactively relabel every past
-- reading with the sensor's new room, which would quietly corrupt the training data for the
-- grey-box RC model (docs/ml/indoor-thermal.md). So a move is: close the old row, insert a new
-- one. See "Moving a sensor" at the bottom of this file.
--
-- Same deployment story as 03/04: on a FRESH database this runs after 02-schema.sql (the seed
-- matches no rows because weather_metrics is empty, and re-runs pick it up later). On an
-- EXISTING deployment the migrate service (docker-compose.yml) applies it on every `up`.

CREATE TABLE IF NOT EXISTS sensor_locations (
    station_id     TEXT             NOT NULL,            -- derived from PASSKEY, as elsewhere
    sensor_type    TEXT             NOT NULL,            -- 'wn31' | 'wh51' | 'gateway' | 'ws69'
    channel        SMALLINT         NOT NULL DEFAULT 0,  -- 0 for single-instance sensors
    room_key       TEXT             NOT NULL,            -- join key: canvas element name / future GeoJSON feature id
    room_label     TEXT             NOT NULL,            -- display name ('Main bedroom')
    priority       SMALLINT         NOT NULL DEFAULT 10, -- tie-break when a room has 2+ sensors; lower wins
    calib_offset_c DOUBLE PRECISION NOT NULL DEFAULT 0,  -- per-unit offset from the co-location test
    installed_at   TIMESTAMPTZ      NOT NULL DEFAULT now(),
    removed_at     TIMESTAMPTZ,                          -- NULL = still in this room
    notes          TEXT,
    PRIMARY KEY (station_id, sensor_type, channel, installed_at),
    CONSTRAINT sensor_locations_interval_ck CHECK (removed_at IS NULL OR removed_at > installed_at)
);

-- Added after the table's first release; harmless on a fresh create.
ALTER TABLE sensor_locations ADD COLUMN IF NOT EXISTS priority SMALLINT NOT NULL DEFAULT 10;

-- Sensor-class priorities. Needed as a backfill, not just as seed values: on a database seeded
-- before this column existed, every row took the column DEFAULT of 10, which would leave the
-- desk room's WN31-vs-gateway tie ambiguous - exactly the flapping this column exists to stop.
-- Only rows still sitting at the default are touched, so a deliberate override is never
-- overwritten. Prefer a real room probe (0) over the indoors-for-now outdoor array (5) over the
-- gateway's self-heated built-in (10); the soil probe (99) never competes since it reports no
-- ambient T/RH at all.
UPDATE sensor_locations sl SET priority = v.priority
FROM (VALUES ('wn31',    0::smallint),
             ('ws69',    5::smallint),
             ('gateway', 10::smallint),
             ('wh51',    99::smallint)) AS v(sensor_type, priority)
WHERE sl.sensor_type = v.sensor_type
  AND sl.priority    = 10          -- untouched column default
  AND sl.priority   <> v.priority;

-- A sensor can be in many rooms over time but only one room *now*.
CREATE UNIQUE INDEX IF NOT EXISTS sensor_locations_active_uq
    ON sensor_locations (station_id, sensor_type, channel)
    WHERE removed_at IS NULL;

COMMENT ON TABLE sensor_locations IS
    'Time-ranged sensor -> room binding. One row per (sensor, room, occupancy interval).';
COMMENT ON COLUMN sensor_locations.priority IS
    'Tie-break when a room holds more than one sensor (the desk room has both WN31 ch2 and '
    'the GW3000 built-in). Lower wins. Prefer a real room probe over the gateway, whose '
    'built-in sensor sits in the self-heating gateway enclosure. Changing which sensor a room '
    'reports is a one-row UPDATE here, with no dashboard edit.';
COMMENT ON COLUMN sensor_locations.calib_offset_c IS
    'Added to the raw reading by the room_readings view. The plain WN31 is +/-1 C while '
    'inter-room deltas are only 1-3 C, so co-locate all units for ~24h and record each '
    'one''s offset here (docs/grafana-floorplan-heatmap.md, "Physical caveat").';

-- Seed the current deployment. station_id is looked up rather than hardcoded, so this works
-- on the NAS without knowing the PASSKEY hash; on a fresh DB it simply seeds nothing until
-- the first reading lands and the migrate service runs again.
--
-- installed_at is '-infinity' deliberately: readings recorded BEFORE this table existed still
-- fall inside the interval and so still get a room name, rather than dropping out of the view.
INSERT INTO sensor_locations (station_id, sensor_type, channel, room_key, room_label, priority, installed_at, notes)
SELECT s.station_id, v.sensor_type, v.channel, v.room_key, v.room_label, v.priority,
       '-infinity'::timestamptz, v.notes
FROM (SELECT DISTINCT station_id FROM weather_metrics) s
CROSS JOIN (VALUES
    ('wn31',    1::smallint, 'bedroom', 'Main bedroom', 0::smallint,
     'WN31 DIP-switch channel 1.'),
    ('wn31',    2::smallint, 'desk',    'Desk room',    0::smallint,
     'WN31 DIP-switch channel 2. Planned move to the living room (Room 1) - close this row then.'),
    ('gateway', 0::smallint, 'desk',    'Desk room',    10::smallint,
     'GW3000 built-in T/RH (tempinf/humidityin). Lowest priority - self-heated enclosure - but '
     'keeps the desk room on the map after WN31 ch2 moves out.'),
    ('ws69',    0::smallint, 'living',  'Room 1',       5::smallint,
     'Outdoor array, currently INDOORS in the living room. Close this row when it goes on the roof.'),
    ('wh51',    1::smallint, 'living',  'Room 1',       99::smallint,
     'Soil probe. Soil moisture only - reports no ambient T/RH, so it never appears in room_readings.')
) AS v(sensor_type, channel, room_key, room_label, priority, notes)
WHERE NOT EXISTS (
    SELECT 1 FROM sensor_locations sl
    WHERE sl.station_id  = s.station_id
      AND sl.sensor_type = v.sensor_type
      AND sl.channel     = v.channel
);

-- Long-format per-room climate readings, room-labelled and calibration-corrected. This is the
-- single source the dashboard's room panels and floor-plan canvas panels query, so the
-- sensor -> room join lives in exactly one place.
--
-- Three sources, because "a room's temperature" comes from three different tables today:
--   wn31    - the actual per-room probes, from sensor_channels
--   gateway - the GW3000's own built-in T/RH, from weather_metrics.temp_in_c / humidity_in
--   ws69    - the outdoor array while it is still indoors; its weather_metrics.temp_c IS the
--             living room's air temperature until it moves to the roof. NOTE this means the
--             living room's temperature and the dashboard's "Outdoor" series are the same
--             number right now, and its dT-vs-outdoor is 0 by construction.
-- The WH51 is absent on purpose: a soil probe reports no ambient temperature or humidity.
--
-- The WN31 branch LEFT JOINs, so the view is a strict superset of the wn31 rows in
-- sensor_channels and can never lose a reading. A channel with no location row (a new sensor
-- someone DIP-switched on, or a reading in the gap between a sensor leaving one room and being
-- registered in the next) falls back to room_key 'ch<N>' / label 'Room <N>' - so the per-room
-- panels keep working, while the floor plan simply doesn't paint it, which is correct: we don't
-- know where it is. The gateway/ws69 branches stay INNER: without a location row there is no
-- room to attribute them to, and every weather_metrics row would otherwise become a phantom.
--
-- One integrity assumption: a single sensor's occupancy intervals must not overlap, or a
-- reading would join twice and be double-counted. The partial unique index above enforces it
-- for active rows; the "Moving a sensor" recipe below keeps it true for historical ones.
--
-- DROP then CREATE, not CREATE OR REPLACE: replacing a view can only APPEND columns, and the
-- column list here has changed shape between revisions. Nothing depends on the view (Grafana
-- only reads it), and psql runs this file in a transaction, so the drop is not observable.
DROP VIEW IF EXISTS room_readings;
CREATE VIEW room_readings AS
SELECT sc.time, sc.station_id,
       COALESCE(sl.room_key,   'ch' || sc.channel)     AS room_key,
       COALESCE(sl.room_label, 'Room ' || sc.channel)  AS room_label,
       COALESCE(sl.priority, 99)                       AS priority,
       sc.sensor_type, sc.channel,
       sc.temp_c + COALESCE(sl.calib_offset_c, 0)      AS temp_c,
       sc.humidity                                    AS humidity,
       sc.batt                                        AS batt
FROM sensor_channels sc
LEFT JOIN sensor_locations sl
  ON  sl.station_id  = sc.station_id
  AND sl.sensor_type = sc.sensor_type
  AND sl.channel     = sc.channel
  AND sc.time >= sl.installed_at
  AND (sl.removed_at IS NULL OR sc.time < sl.removed_at)
WHERE sc.sensor_type = 'wn31'

UNION ALL

SELECT wm.time, wm.station_id, sl.room_key, sl.room_label, sl.priority, sl.sensor_type, sl.channel,
       wm.temp_in_c + sl.calib_offset_c,
       wm.humidity_in,
       NULL::double precision        -- the gateway is mains-powered; no battery flag
FROM weather_metrics wm
JOIN sensor_locations sl
  ON  sl.station_id  = wm.station_id
  AND sl.sensor_type = 'gateway'
  AND wm.time >= sl.installed_at
  AND (sl.removed_at IS NULL OR wm.time < sl.removed_at)

UNION ALL

SELECT wm.time, wm.station_id, sl.room_key, sl.room_label, sl.priority, sl.sensor_type, sl.channel,
       wm.temp_c + sl.calib_offset_c,
       wm.humidity,
       wm.wh65_batt::double precision
FROM weather_metrics wm
JOIN sensor_locations sl
  ON  sl.station_id  = wm.station_id
  AND sl.sensor_type = 'ws69'
  AND wm.time >= sl.installed_at
  AND (sl.removed_at IS NULL OR wm.time < sl.removed_at);

COMMENT ON VIEW room_readings IS
    'Room-labelled, calibration-corrected climate readings from every sensor that reports '
    'ambient T/RH (WN31 channels, GW3000 built-in, and the WS69 while it is still indoors).';

-- Grafana reads as the read-only role created by 06-grafana-ro.sql. Its ALTER DEFAULT
-- PRIVILEGES already covers objects created later, but grant explicitly so this file also
-- works when run standalone against an older database. Guarded so it is a no-op if 06 has
-- not run yet.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_ro') THEN
        GRANT SELECT ON sensor_locations, room_readings TO grafana_ro;
    END IF;
END $$;

-- Moving a sensor
-- ---------------
-- Two statements, in one transaction. Example: WN31 ch2 leaves the desk room for the living
-- room. Do NOT update room_key in place - that would relabel all of its history.
--
--   BEGIN;
--   UPDATE sensor_locations SET removed_at = now()
--    WHERE sensor_type = 'wn31' AND channel = 2 AND removed_at IS NULL;
--   INSERT INTO sensor_locations (station_id, sensor_type, channel, room_key, room_label, installed_at)
--   SELECT station_id, 'wn31', 2, 'living', 'Room 1', now()
--     FROM sensor_locations WHERE sensor_type = 'wn31' AND channel = 2
--    ORDER BY installed_at DESC LIMIT 1;
--   COMMIT;
--
-- Retiring a sensor from indoor duty (the WS69 going up on the roof) is just the UPDATE, with
-- no matching INSERT - the living room then reads "no sensor" on the floor plan until WN31 ch2
-- takes its place.
