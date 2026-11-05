# Glucoscope

A self-hosted, server-rendered web app for viewing and sharing blood glucose data. CGM readings arrive from xDrip+ through a Nightscout-compatible `/api/v1/entries` endpoint. Built with Node.js, Express, LiquidJS, and PostgreSQL using MVC architecture.

CSE 340 Web Backend Development final project.

> Work in progress. See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the design and roadmap.

## Getting started

Requires Node.js 22.9 or newer and PostgreSQL.

1. Install dependencies: `npm install`
2. Copy `.env.example` to `.env` and set `DATABASE_URL` for your database
3. Start the development server, which restarts on file changes: `npm run dev`
4. Open http://localhost:3000

`GET /health` returns `200` when the app can reach the database and `503` when it cannot.

In production, set `NODE_ENV=production` and run `npm start`.
