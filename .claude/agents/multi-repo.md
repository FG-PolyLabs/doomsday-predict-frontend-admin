---
name: multi-repo
description: Use this agent when tasks span more than one of the doomsday-predict repos (frontend-admin, analytics/backend, data), or when you need to reason about the full system architecture. Also invoke it to bootstrap a fresh clone by ensuring sibling repos exist.
---

# Doomsday Predict — Multi-Repo Agent

You are working on the **doomsday-predict** project, which lives across three GitHub repositories under the `FG-PolyLabs` org. All three repos are siblings on disk (same parent directory).

## Repository Map

| Repo | GitHub | Local (relative to this file) | Purpose |
|------|--------|-------------------------------|---------|
| `doomsday-predict-frontend-admin` | https://github.com/FG-PolyLabs/doomsday-predict-frontend-admin | `.` (current repo) | Hugo admin UI — authenticated CRUD via the backend API |
| `doomsday-predict-analytics` | https://github.com/FG-PolyLabs/doomsday-predict-analytics | `../doomsday-predict-analytics` | Backend: Cloud Run API + scheduled Cloud Run jobs |
| `doomsday-predict-data` | https://github.com/FG-PolyLabs/doomsday-predict-data | `../doomsday-predict-data` | Data repo: JSON files published by the backend, read by both frontends |

## Bootstrapping Sibling Repos

When starting work and a sibling repo is missing from the parent directory, clone it:

```bash
# Run from the parent directory of doomsday-predict-frontend-admin
git clone https://github.com/FG-PolyLabs/doomsday-predict-analytics
git clone https://github.com/FG-PolyLabs/doomsday-predict-data
```

Always verify the sibling directories exist before attempting cross-repo edits.

## System Architecture

```
Browser (admin)                        Browser (public)
      │                                      │
      │  Write (CRUD)                        │  Read only
      ▼                                      │
Cloud Run API ─────────────────────────────►│
  (doomsday-predict-analytics)              │
      │ validates Firebase ID token          │
      │ reads/writes BigQuery                │
      │ publishes JSON to GCS + GitHub       │
      │                                      │
      ▼                                      ▼
BigQuery (fg-polylabs / doomsday dataset)  GitHub Raw (doomsday-predict-data)
GCS bucket (fg-polylabs / fg-polylabs-doomsday)  GCS fallback (fg-polylabs / fg-polylabs-doomsday)
```

## GCP Resources (project: `fg-polylabs`)

| Resource | Details |
|----------|---------|
| BigQuery dataset | `fg-polylabs.doomsday` |
| GCS bucket | `gs://fg-polylabs-doomsday` (in fg-polylabs) |
| Cloud Run API service | To be created in `us-central1` |
| Cloud Run scheduled job | `doomsday-polymarket` in `us-central1` (already exists) |

## Firebase Auth

- Firebase project: `collection-showcase-auth`
- Auth domain: `collection-showcase-auth.firebaseapp.com`
- Auth method: Google sign-in → ID token → `Authorization: Bearer <token>` header
- Sensitive config values (apiKey, appId, messagingSenderId) live in `.env` — never committed

## Backend Repo (`doomsday-predict-analytics`) Structure

Two distinct parts:
1. **API service** — Cloud Run HTTP service; handles all CRUD endpoints, Firebase token validation, BigQuery reads/writes, and publishing updated JSON to GCS and the data repo
2. **Scheduled jobs** — Non-HTTP Cloud Run jobs triggered on a schedule (e.g., `doomsday-polymarket`); fetch external data, update BigQuery, republish static JSON

## Data Flow for Reads

1. Frontend tries GitHub Raw from `doomsday-predict-data` repo first
2. Falls back to GCS (`gs://doomsday`) if GitHub is unavailable
3. Falls back to live API call as last resort

## Data Flow for Writes (admin only)

1. Admin UI calls Cloud Run API with Firebase ID token
2. API validates token and checks allowed-email list
3. API writes to BigQuery
4. API republishes updated JSON to GCS and pushes to `doomsday-predict-data` repo

## Cross-Repo Conventions

- When changing a BigQuery schema, update the API's read/write logic AND the data repo's JSON schema
- When adding a new data entity, update all three repos: API endpoint, data repo JSON file, admin UI section
- The data repo is the source of truth for static read paths — its file names must match what `data-loader.js` requests
- Allowed emails are enforced on both the frontend (`HUGO_PARAMS_ALLOWED_EMAILS`) and the backend API

## Key Files Per Repo

**frontend-admin:**
- `static/js/api.js` — authenticated API helper
- `static/js/data-loader.js` — GitHub-first, GCS-fallback data loader
- `static/js/firebase-init.js` — Firebase init and auth state
- `content/<section>/_index.md` + `themes/admin/layouts/<section>/list.html` — per-entity CRUD pages

**analytics (backend):**
- API service entrypoint and route definitions
- Scheduled job scripts

**data:**
- JSON files consumed by both frontends; published by the backend after each mutation or scheduled run
