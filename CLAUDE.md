# doomsday-predict-frontend-admin

## Project Overview

Hugo-based admin frontend for the **doomsday-predict** system. Authenticated users can create, edit, and delete records via the backend API. Data is read from static JSON (GitHub → GCS fallback) and written through Cloud Run.

This is **one of three repos** in the project — see the Multi-Repo section below.

## Multi-Repo Architecture

All three repos are siblings on disk (same parent directory).

| Repo | Local path | GitHub | Purpose |
|------|-----------|--------|---------|
| `doomsday-predict-frontend-admin` | `.` | https://github.com/FG-PolyLabs/doomsday-predict-frontend-admin | This repo — admin UI |
| `doomsday-predict-analytics` | `../doomsday-predict-analytics` | https://github.com/FG-PolyLabs/doomsday-predict-analytics | Backend: Cloud Run API + scheduled jobs |
| `doomsday-predict-data` | `../doomsday-predict-data` | https://github.com/FG-PolyLabs/doomsday-predict-data | Published JSON data files |

Run `./setup.sh` from this repo root to clone the sibling repos automatically.

For cross-repo tasks, use the **multi-repo** custom agent (`.claude/agents/multi-repo.md`).

## GCP Resources (project: `fg-polylabs`)

| Resource | Details |
|----------|---------|
| BigQuery dataset | `fg-polylabs.doomsday` |
| GCS bucket | `gs://fg-polylabs-doomsday` |
| Cloud Run API | `https://doomsday-api-846376753241.us-central1.run.app` |
| Cloud Run scheduled job | `doomsday-polymarket` (us-central1) — already exists |

## This Repo's Architecture

- **Framework:** [Hugo](https://gohugo.io/) — static site generator with Go templates
- **Theme:** Custom theme (`themes/admin/`) — Bootstrap 5, no external theme dependency
- **Auth:** Firebase Authentication (`collection-showcase-auth` project) — Google sign-in; ID token attached to all API calls
- **Backend communication:** `api()` helper in `static/js/api.js` — attaches `Authorization: Bearer <token>` automatically
- **Data reads:** `loadFromGitHub()` / `loadFromGCS()` in `static/js/data-loader.js` — jsDelivr CDN (GitHub) first, GCS fallback. Uses jsDelivr instead of raw.githubusercontent.com to guarantee reliable CORS headers.
- **Deployment:** GitHub Pages via GitHub Actions (`.github/workflows/deploy.yml`)

## Key Files

| Path | Purpose |
|------|---------|
| `hugo.toml` | Hugo config — title, description, params defaults |
| `themes/admin/layouts/` | Hugo templates (baseof, list, index) |
| `themes/admin/layouts/partials/` | head, navbar, footer, scripts partials |
| `static/js/firebase-init.js` | Firebase app init, `authSignOut()`, `isEmailAllowed()`, auth state listener |
| `static/js/api.js` | Authenticated `api(method, path, body)` helper + `qs()` query builder |
| `static/js/app.js` | Global `showToast()` utility |
| `static/js/data-loader.js` | `loadFromGitHub()` / `loadFromGCS()` / `loadJsonData()` — jsDelivr-first, GCS-fallback data fetching |
| `static/css/app.css` | Minimal style overrides on top of Bootstrap 5 |
| `.env.example` | Template for all environment variables |

## Auth Flow

1. User lands on the site and is prompted to sign in via Firebase (Google).
2. Firebase issues an ID token.
3. Frontend attaches the token as `Authorization: Bearer <token>` on all backend requests.
4. Backend validates the token via Firebase Admin SDK.
5. Access is further restricted to `ALLOWED_EMAILS`, enforced on both frontend and backend.

## Development Notes

- Hugo config lives in `hugo.toml`
- Firebase config goes in `.env` — never commit this file (sensitive fields: apiKey, appId, messagingSenderId)
- Non-sensitive Firebase fields (authDomain, projectId, storageBucket) are pre-filled in `.env.example`
- Environment variables are injected as `HUGO_PARAMS_*` and map to `.Site.Params.*` in templates
- `split .Site.Params.allowed.emails ","` in `head.html` converts the comma-separated email string to a JS array
- To add a new CRUD section: create `content/<section>/_index.md`, add a nav link in `navbar.html`, add `themes/admin/layouts/<section>/list.html`, set `RESOURCE_PATH` to match the backend endpoint
