# visionEAE

**Student 360° View** — a proof of concept for Universidad Icesi that gives a student and their
support team a single, trustworthy view of academic, financial, learning-platform and wellbeing
signals, so risk situations can be caught and acted on early.

📄 **[Full architecture and delivery overview →](https://github.com/visionEAE/.github/blob/main/docs/OVERVIEW.md)**
— what was built, why it's split the way it is, the two authorization layers, the audit trail,
the CQRS backend architecture, the end-to-end demonstration thread, and **demo credentials** to
try the student and the student-support perspectives yourself.

**Status:** local-environment proof of concept (stage 1 of 2). Nothing here is deployed anywhere
reachable; it runs entirely on a developer's machine. All data is fictional and seeded for the demo.

## Repositories (private to the organisation)

| Repository | Role |
|---|---|
| `student360-infra` | Documentation, local infrastructure (PostgreSQL, Adminer), orchestration `Makefile`, demo scripts |
| `student360-common` | Shared library: JSON logging, correlation, identity context, audit, outbox, service tokens |
| `student360-auth-service` | Custom SSO: tokens, rotating refresh tokens, reuse detection, JWKS |
| `student360-gateway` | Single entry point: token validation, coarse authorization, identity propagation |
| `student360-core-service` | Simulated SIS + ERP: student identity, academic and financial status |
| `student360-lms-service` | Simulated learning platform: courses, submissions, access logs, engagement signals |
| `student360-support-service` | Wellbeing entries, the risk rule, alerts, intervention plans, advisor reports and requests |
| `student360-frontend` | Single-page app for both the student and the advisor experience |

Each service lives in its own repository because each is an independently deployable unit in a
future cloud stage. Conventions shared by every repository: [CONTRIBUTING.md](https://github.com/visionEAE/.github/blob/main/CONTRIBUTING.md).
