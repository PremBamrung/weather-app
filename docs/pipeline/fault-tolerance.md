# Fault Tolerance & Backfill

The NAS will occasionally be offline — kernel upgrades, ZFS scrubs, container
redeployments. The GW3000's local buffer keeps the time series continuous across those gaps.

## MicroSD fail-safe

- Insert a small **≤ 32 GB MicroSD** card, formatted **FAT32**, into the GW3000 slot.
- When enabled, the gateway continuously writes local backup `.csv` files, acting as an
  isolated edge-logger independent of the NAS.
- This decouples data capture from NAS availability: the NAS can go down without losing data.

## CSV exposure

The gateway serves its buffered CSVs over its internal web server:

```
http://<GATEWAY_IP>:81/YYYYMM.csv
```

One file per month (`YYYYMM`), fetchable over the LAN.

## Backfill pipeline

A maintenance cron job on the NAS reconciles the database against the SD buffer:

1. **Scan** TimescaleDB for temporal gaps (intervals with no rows where rows are expected).
2. **Fetch** the matching `YYYYMM.csv` from `http://<GATEWAY_IP>:81/`.
3. **Slice** the CSV rows that fall inside each gap.
4. **Convert** Imperial → metric (same logic as live ingestion — see
   [payload format](payload-format.md)).
5. **INSERT** the backfilled rows to restore continuity.

```
              gap detected
TimescaleDB ─────────────────► [ backfill cron ]
                                     │ GET http://<GATEWAY_IP>:81/YYYYMM.csv
                                     ▼
                            [ GW3000 SD buffer (CSV) ]
                                     │ slice gap rows, convert units
                                     ▼
                            INSERT INTO weather_metrics
```

## Implementation notes

- **Idempotency:** dedupe on `(station_id, time)` — use `ON CONFLICT DO NOTHING` (or a
  unique index) so re-running the backfill can't create duplicates.
- **Authoritative timestamps:** during backfill, trust the CSV row timestamps for ordering
  (the gap being filled is historical, not live).
- **Cadence:** run frequently enough that a gap is still within the SD card's retention, but
  it need not be real-time — hourly or a few times a day is fine.
- **Compression interaction:** backfilling into an already-compressed chunk may require
  decompress → insert → recompress; prefer backfilling before the compression policy closes
  the chunk, or handle the decompress step explicitly.
