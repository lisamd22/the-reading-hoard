# hoard-api

Share a link → get the books in the video. One process, FastAPI, SQLite, Gemini.

```
cp .env.example .env   # fill in GEMINI_API_KEY at minimum
set -a; source .env; set +a
.venv/bin/uvicorn app.main:app --port 8080 --reload
```

Try it:
```
curl -X POST localhost:8080/v1/jobs -H 'Content-Type: application/json' \
  -H "X-App-Key: $APP_KEY" -H 'X-Install-ID: dev-1' \
  -d '{"url":"https://vm.tiktok.com/ZGdxo8VFD/","clientJobID":"any-unique-string"}'
curl -N localhost:8080/v1/jobs/<jobID>/events
```

Spike (measures the real pipeline on the real links, writes `spike/RESULTS.md`):
```
.venv/bin/python spike/run.py
.venv/bin/python spike/run.py --model gemini-3.8-flash
```

Tests: `.venv/bin/pytest`.

Deployed as Fly app `hoard-api` (https://hoard-api.fly.dev, one machine, volume `hoard_data`
for the SQLite db). Secrets are set with `fly secrets`, never in `fly.toml`.
```
fly deploy --app hoard-api --ha=false
fly logs --app hoard-api --no-tail
```

## How each platform is fetched
| | |
|---|---|
| TikTok | Own mobile page JSON (iPhone UA) → `playAddr` / `imagePost.images[]`. Free — but TikTok serves a shell page to datacenter IPs, so on Fly `TIKTOK_VENDOR_FIRST=1` tries ScrapeCreators first and the page second. |
| Pinterest | Own pin page → direct MP4 or 736px image. Free. |
| YouTube | No fetch — Gemini ingests the URL. Data API for the description (optional key). |
| Instagram | ScrapeCreators for the video (key). Caption floor from `og:description` without it. |

Media bytes are never stored. Results are cached 30 days by canonical post id.
