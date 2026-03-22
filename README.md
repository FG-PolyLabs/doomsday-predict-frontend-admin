# doomsday-predict-frontend-admin

Hugo-based admin UI for the doomsday-predict project. Authenticated users manage records via the backend API; data is read from static JSON published to GitHub and GCS.

## Multi-Repo Project

This is one of three repos:

| Repo | Purpose |
|------|---------|
| [doomsday-predict-frontend-admin](https://github.com/FG-PolyLabs/doomsday-predict-frontend-admin) | This repo — admin UI (Hugo + Firebase Auth) |
| [doomsday-predict-analytics](https://github.com/FG-PolyLabs/doomsday-predict-analytics) | Backend: Cloud Run API + scheduled jobs |
| [doomsday-predict-data](https://github.com/FG-PolyLabs/doomsday-predict-data) | Published JSON data files (read by both frontends) |

Clone everything at once:

```bash
git clone https://github.com/FG-PolyLabs/doomsday-predict-frontend-admin
cd doomsday-predict-frontend-admin
./setup.sh
```

## Architecture

```
Admin browser
      │
      │  Reads (static JSON)
      ├──────────────────────► GitHub Raw (doomsday-predict-data)
      │                               └── GCS fallback (gs://doomsday)
      │
      │  Writes (CRUD)
      └──────────────────────► Cloud Run API (doomsday-predict-analytics)
                                     │ Firebase ID token validated
                                     │ Read/write BigQuery (fg-polylabs.doomsday)
                                     └── Publish JSON → GCS + doomsday-predict-data repo
```

## Tech Stack

- **[Hugo](https://gohugo.io/)** — static site generator
- **Bootstrap 5** — UI framework
- **Firebase Auth** (`collection-showcase-auth` project) — Google sign-in, ID token issuance
- **GitHub Pages** — hosting via GitHub Actions
- **GCP project `fg-polylabs`** — BigQuery (`doomsday` dataset), GCS (`doomsday` bucket), Cloud Run

## Local Development

1. Copy `.env.example` to `.env` and fill in the sensitive Firebase fields (apiKey, appId, messagingSenderId):

```bash
cp .env.example .env
# edit .env — non-sensitive fields are pre-filled
```

2. Start the dev server:

```bash
source .env && hugo server --port 1313
```

3. Open [http://localhost:1313](http://localhost:1313) and sign in with an allowed email.

## Configuration

All config is supplied via `HUGO_PARAMS_*` environment variables. See `.env.example` for the full list.

### GitHub Actions Variables (non-sensitive)

| Variable | Purpose |
|----------|---------|
| `GITHUB_PAGES_URL` | Full GitHub Pages URL |
| `HUGO_PARAMS_FIREBASE_AUTH_DOMAIN` | Firebase auth domain |
| `HUGO_PARAMS_FIREBASE_PROJECT_ID` | Firebase project ID |
| `HUGO_PARAMS_FIREBASE_STORAGE_BUCKET` | Firebase storage bucket |
| `HUGO_PARAMS_BACKENDURL` | Backend Cloud Run API base URL |
| `HUGO_PARAMS_ALLOWED_EMAILS` | Comma-separated admin email whitelist |
| `HUGO_PARAMS_GCS_DATA_BUCKET` | GCS bucket for static data fallback |
| `HUGO_PARAMS_GITHUB_DATA_REPO` | GitHub data repo (e.g. `FG-PolyLabs/doomsday-predict-data`) |

### GitHub Actions Secrets (sensitive)

| Secret | Purpose |
|--------|---------|
| `HUGO_PARAMS_FIREBASE_API_KEY` | Firebase API key |
| `HUGO_PARAMS_FIREBASE_APP_ID` | Firebase app ID |
| `HUGO_PARAMS_FIREBASE_MESSAGING_SENDER_ID` | Firebase messaging sender ID |

## Adding a New Section

1. Create the content directory:
   ```bash
   mkdir -p content/my-section
   echo $'---\ntitle: "My Section"\n---' > content/my-section/_index.md
   ```
2. Add a nav link in `themes/admin/layouts/partials/navbar.html`.
3. Create a layout at `themes/admin/layouts/my-section/list.html` (or rely on the default).
4. Set `RESOURCE_PATH` in the page script to match your backend endpoint.
5. Add the corresponding API route in `doomsday-predict-analytics`.
