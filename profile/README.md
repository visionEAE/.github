# visionEAE

Architectural proof of concept for **Student 360° View** (Universidad Icesi): a consolidated
view of a student's academic, financial, learning-platform and wellbeing signals, built so the
support team can detect risk early.

| Repository | Role |
|---|---|
| `student360-infra` | Documentation (context, implementation plan), local infrastructure (PostgreSQL, Adminer), orchestration Makefile, demo scripts |
| `student360-common` | Shared library: JSON logging, correlation, identity context, audit, outbox, service tokens |
| `student360-auth-service` | Custom SSO: tokens, rotating refresh tokens, reuse detection, JWKS |
| `student360-gateway` | Single entry point: JWT validation, coarse authorization, identity propagation |
| `student360-core-service` | Simulated SIS + ERP: student identity, academic and financial status |
| `student360-lms-service` | Simulated LMS: courses, submissions, access logs, engagement signals |
| `student360-support-service` | Wellbeing entries, risk rules, alerts, intervention plans |
| `student360-frontend` | Minimal SPA |

Each service lives in its own repository because each is an independent Cloud Run deployable
in stage 2. Conventions for all repositories: [CONTRIBUTING.md](../CONTRIBUTING.md).
