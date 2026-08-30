# Student 360° View — architecture and delivery overview

**Status:** local-environment architectural proof of concept (stage 1 of 2). Everything described
here runs on a developer's machine; nothing is deployed to a reachable environment. Every person,
grade, balance and message in this document is fictional demo data seeded for the walkthrough.

This page is the organisation-level record of what was built, why, and how to see it running.
Repository-level detail (commit history, code, individual READMEs) lives in each `student360-*`
repository, private to the organisation; this page is the public summary.

---

## 1. What this is

Student 360° View consolidates a student's academic, financial, learning-platform activity and
self-reported wellbeing into a single view, so that a university's student-support team can spot
risk situations early and act on them — and so a student can see their own standing in one place.

The proof of concept demonstrates, end to end and with real running services (not diagrams):

- identity travels correctly from login through every downstream call;
- authorization is enforced at **two independent layers** — coarse (role → route) and fine-grained
  (does *this* caller have a real relationship with *this* student);
- one service **orchestrates** two others synchronously and combines their answers into a decision;
- everything that happens is **traceable and auditable**, including denied attempts;
- every state change is recorded in a way that could feed a data warehouse in production.

## 2. The five services

| Service | Responsibility | Port |
|---|---|---|
| `gateway` | Single entry point. Validates the access token, enforces coarse role/route rules, strips the user's token and forwards a signed service identity plus the caller's identity as headers. | 8080 |
| `auth-service` | Custom SSO. Issues short-lived access tokens and rotating refresh tokens, detects refresh-token replay, exposes its public keys. | 8081 |
| `core-service` | Simulates the institution's student and financial systems (SIS + ERP). Source of truth for identity, academic status, financial status. | 8082 |
| `lms-service` | Simulates the learning platform. Courses, submissions, access logs, and the *interpreted* engagement signal (days since last access, on-time rate, idle courses). | 8083 |
| `support-service` | Everything new: wellbeing entries, the risk rule, alerts, intervention plans, advisor reports and requests. The only service that calls the other two synchronously and composes a decision. | 8084 |
| `frontend` | Single-page app: the two experiences below. | 5173 |

Why the learning platform is its own service rather than folded into the SIS/ERP one: it produces
high-frequency behavioural *signals*, not official state, and — as at the real institution — it is
a third-party system with its own lifecycle. Keeping it separate is also what makes the
orchestration in `support-service` genuine rather than a single database read.

## 3. Two-layer authorization

1. **Coarse, at the gateway**: a route belongs to a set of roles (`STUDENT`, `ADVISOR`, `ADMIN`).
   A token without the right role never reaches a service — `403` before anything downstream runs.
2. **Fine-grained, inside each service**: a student may read only their own record (`ref` claim
   equals the id requested); an advisor may read only a student they hold an *active assignment*
   to. Wrong relationship → `403`, **and an audit record explaining why**, recorded before the
   response leaves.

Both layers are exercised live in the demonstration thread (§6).

## 4. Audit trail

Every access to sensitive data — allowed or denied — writes one row to an append-only audit table:
who, what, about which student, when, under which authorization relationship (`SELF`,
`ASSIGNMENT`, `ADMIN_ROLE`, or `NONE` for a denial), and the correlation id of the request. The
database itself enforces append-only: each service's database role has `INSERT`/`SELECT` on the
table and nothing else — no application bug can rewrite history.

A single request that crosses three services (submit a wellbeing entry → the rule calls
`core-service` and `lms-service`) leaves three correlated rows, one per service, all sharing the
same request id — reconstructible with one query.

## 5. Backend architecture: CQRS + ports and adapters

Every service separates **commands** (writes — record a wellbeing entry, create an alert, accept
an intervention plan) from **queries** (reads — the 360° view, the advisor's student list), each
handled by its own class. Handlers depend only on interfaces (`domain/port`): a repository, a
client to another service, a clock. Nothing about *how* data is stored or fetched leaks into
business logic — an interface can be swapped (a different database, a different transport to
another service, a cloud-native equivalent) without touching a single handler.

This is also what stage 2 (cloud deployment) will lean on: the interfaces that will point at
managed services in stage 2 — event publishing, service-to-service authentication, secret storage
— already exist and are already implemented locally; moving to the cloud swaps the implementation
behind the interface, not the business logic.

## 6. The demonstration thread

The proof of concept is built to make this sequence work, live, in one run:

1. A student logs in; the decoded token shows their role and their identity claim.
2. Their 360° view loads academic and financial status from `core-service` and engagement from
   `lms-service`, through the gateway, with the user's own token never reaching either service.
3. A request for another student's data is denied at the fine-grained layer; a request to an
   advisor-only route with a student token is denied at the coarse layer.
4. The student submits a low wellbeing entry (three dimensions: economic, academic, emotional).
   `support-service` persists it, then evaluates a risk rule that reads the entry together with
   signals fetched **synchronously** from `core-service` and `lms-service`.
5. When the signals converge (low wellbeing **and** disengagement or financial strain, or all
   three), the rule raises an alert with an explicit list of which conditions fired and a
   suggested intervention plan — never a black-box score.
6. The assigned advisor sees the alert in their inbox, opens it, and the access is recorded with
   the relationship that authorized it.
7. An advisor **without** an active assignment to that student is denied, and that denial is
   recorded too.
8. Querying the audit table by the original request id reconstructs the whole path across
   services.
9. Replaying an already-used refresh token revokes the entire session family — a compromised
   token can never be used again, and neither can the legitimate one that follows it, forcing a
   clean re-login.

## 7. Frontend

A React single-page app built with **atomic design** (atoms → molecules → organisms → templates →
pages) against the visual design produced for this project, so the same building blocks are reused
across the student and advisor experiences rather than duplicated per screen. The access token is
kept in memory only (never in browser storage); the refresh token lives in an `HttpOnly` cookie;
concurrent `401`s share a single refresh attempt so they can never look like a token replay.

## 8. What "stage 2" changes

Stage 1 runs entirely on a developer's machine: PostgreSQL and the five services in Docker
Compose, a locally-signed token standing in for service-to-service authentication, domain events
written to an outbox table instead of published anywhere. Every one of those is a named interface
today; stage 2 (a future cloud deployment) plans to swap:

| Local (stage 1) | Cloud (stage 2) |
|---|---|
| Locally-signed service token | Cloud-provider–signed identity token |
| Outbox table | Message broker + subscription into a data warehouse |
| Docker Compose PostgreSQL | Managed database |
| File-based signing key | Managed secret storage |
| JSON logs on stdout | Centralised log platform |

No stage 2 infrastructure exists yet; this row is a statement of design intent, verifiable by
reading the interfaces in the code.

## 9. Try it yourself — demo credentials

Stage 1 only runs locally — these accounts exist solely inside a disposable local database seeded
for this demo. Every account uses the password below; none of this is a real institutional system.

**Password for every account:** `student360`

| Perspective | Email | What you see |
|---|---|---|
| Student — at-risk case | `maria.rojas@u.icesi.edu.co` | Own 360° view, an active high-severity alert generated against her own data, "Mi espacio seguro" wellbeing form |
| Student — on track | `ana.torres@u.icesi.edu.co` | Own 360° view with no open alert |
| Student — mixed profile | `juan.gomez@u.icesi.edu.co`, `luis.gomez@u.icesi.edu.co`, `santiago.molina@u.icesi.edu.co`, `isabella.zapata@u.icesi.edu.co`, `andres.ruiz@u.icesi.edu.co` | Other seeded students, each with a different mix of academic/financial/wellbeing standing |
| Student-support team | `carlos.mejia@icesi.edu.co` | "Mis estudiantes" overview (6 advisees, a real spread of risk levels), alert inbox, interventions, reports |
| Student-support team | `diana.perez@icesi.edu.co` | A second advisor's caseload (4 advisees) — also the one who is correctly **denied** access to María Rojas's alert, since she holds no active assignment to her |

The advisor overview and 360° views are populated with a full spread of academic, financial and
emotional standing across ten seeded students — including cases where the risk comes from only
one dimension (purely financial, or purely academic) and cases where all three converge, matching
what an early-intervention system needs to distinguish.
