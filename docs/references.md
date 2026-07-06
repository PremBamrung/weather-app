# References & Datasheets

Authoritative sources for the hardware, data feeds, and datasets referenced throughout these
docs. (These were **not** present in the original design document — they are canonical links
gathered to back up the specs. Verified July 2026.)

## Hardware — Ecowitt

### WS69 7-in-1 outdoor sensor array
- Product page: https://shop.ecowitt.com/products/ws69
- **Operation manual (PDF):** https://oss.ecowitt.net/uploads/20250625/ws69-update.pdf
- Older manual (PDF): https://osswww.ecowitt.net/uploads/20220905/WS69%20Manual.pdf
- Manual mirror (ManualsLib): https://www.manualslib.com/manual/3776541/Ecowitt-Ws69.html

Confirmed specs (from the manual): measures rain, wind speed, wind direction, temperature,
humidity, solar light intensity, **and UV index**; temp range −40 °C to 60 °C (±1 °C);
humidity 1–99 %RH (±5 %); rainfall 0–9999 mm (±10 %, 0.3 mm resolution); RF range up to
100 m / 330 ft; **reports every 16 s**; solar panel + 2×AA backup.

### GW3000 gateway
- Product page: https://shop.ecowitt.com/products/gw3000-gw3010
- Ecowitt detail page: https://www.ecowitt.com/shop/goodsDetail/336
- **Manual (PDF):** https://oss.ecowitt.net/uploads/20241204/GW3000Manual.pdf
- GW3002 kit (WS69 + GW3000): https://shop.ecowitt.com/products/gw3002

Confirmed specs: Wi-Fi (2.4 GHz, 802.11 b/g/n) **and** LAN/Ethernet; **built-in temperature,
humidity and barometric sensors** (this is why pressure is gateway-side); SD card port;
915 MHz (North America).

### Expansion sensors
- WN31 / WH31 multi-channel temp/humidity: https://shop.ecowitt.com/products/wh31
- WH51 soil moisture probe: https://shop.ecowitt.com/products/wh51
- WS90 "Wittboy" solid-state array (alternative): https://shop.ecowitt.com/products/ws90

## Weather data feeds

### Environment & Climate Change Canada — HRDPS (2.5 km NWP)
- Datamart HRDPS readme: https://eccc-msc.github.io/open-data/msc-data/nwp_hrdps/readme_hrdps-datamart_en/
- MSC Open Data root: https://eccc-msc.github.io/open-data/msc-data/readme_en/
- GRIB2 download root: https://dd.weather.gc.ca/model_hrdps/continental/
- Dataset (Open Government): https://open.canada.ca/data/en/dataset/9eaf8b65-a734-432e-925c-7fbe8fc65670

HRDPS: 2.5 km grid, 48-hour forecasts, updated 4×/day, GRIB2 over HTTPS.

### Open-Meteo — historical proxy data (McTavish sandbox)
- Historical Weather API docs: https://open-meteo.com/en/docs/historical-weather-api
- API root / docs: https://open-meteo.com/en/docs
- Endpoint: `GET https://archive-api.open-meteo.com/v1/archive` (JSON, no auth for non-commercial)

Hourly data from 1940 onward (ERA5 / ERA5-Land reanalysis).

### METAR (aviation surface observations)
- NAV CANADA / aviation weather METARs for **YUL** (Trudeau), **YHU** (St-Hubert),
  **YMX** (Mirabel). Also retrievable hourly via Open-Meteo for the same coordinates.

## Montreal geospatial (static spatial features)

Portal: https://donnees.montreal.ca

- Aerial LiDAR 2015: https://donnees.montreal.ca/dataset/lidar-aerien-2015
- Digital Surface Model (MNS, 1 m raster) — used for **SVF**: https://donnees.montreal.ca/dataset/modele-numerique-de-surface-mns
- Digital Canopy Model (MNC) — used for **roughness z₀**: https://donnees.montreal.ca/dataset/modele-numerique-de-canopee-mnc
- Canopée (tree canopy): https://donnees.montreal.ca/dataset/canopee

## Software stack

- TimescaleDB docs: https://docs.timescale.com/
- TimescaleDB Docker image: `timescale/timescaledb:latest-pg16` — https://hub.docker.com/r/timescale/timescaledb
- FastAPI docs: https://fastapi.tiangolo.com/
- LightGBM docs: https://lightgbm.readthedocs.io/

> Note: exact `oss.ecowitt.net` PDF paths can rotate when Ecowitt revises a manual; if a
> link 404s, start from the product page and follow its "Download" / "Manual" link.
