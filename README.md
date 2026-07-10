# EventMeet

Monorepo containing the EventMeet backend and frontend.

| Directory | Stack | Dev port |
|---|---|---|
| [`backend/`](backend/README.md) | Ruby on Rails 8 (API/app server) | `3000` |
| [`frontend/`](frontend/README.md) | Next.js (TypeScript, App Router) | `5173` |

## Getting started

### Backend

```sh
cd backend
bin/setup
bin/dev
```

Runs at http://localhost:3000.

### Frontend

```sh
cd frontend
npm install
npm run dev
```

Runs at http://localhost:5173.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs backend (Rubocop, Brakeman, RSpec) and frontend (lint, build) checks independently on every push and pull request.
