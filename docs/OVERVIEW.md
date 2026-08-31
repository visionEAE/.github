# Student 360° View — architecture and delivery overview

**Status:** architectural proof of concept, both stages complete. Stage 1 (local, six services in
Docker Compose) and stage 2 (cloud deployment on GCP, verified live) are both real, running
systems — not diagrams. Every person, grade, balance and message in this document is fictional
demo data seeded for the walkthrough.

This page is the organisation-level record of what was built, why, and how to see it running.
Repository-level detail (commit history, code, individual READMEs) lives in each repository,
private to the organisation; this page is the public summary.

---

## 1. What this is

Student 360° View consolidates a student's academic, financial, learning-platform activity and
self-reported wellbeing into a single view, so that a university's student-support team can spot
risk situations early and act on them — and so a student can see their own standing in one place.

The proof of concept demonstrates, end to end and with real running services:

- identity travels correctly from login through every downstream call, in local Docker Compose
  and again in Cloud Run behind Google-signed identity tokens;
- authorization is enforced at **two independent layers** — coarse (role → route) and fine-grained
  (does *this* caller have a real relationship with *this* student);
- one service **orchestrates** two others synchronously and combines their answers into a decision;
- a fifth service models a genuinely different kind of data — a support network — as a graph;
- everything that happens is **traceable and auditable**, including denied attempts;
- every state change is recorded transactionally and fed, asynchronously, into a data warehouse;
- the whole thing deploys itself: content-hash-gated builds, digest-based rollouts, no
  service-account keys anywhere.

## 2. The repositories

One repository per deployable unit — each service is an independent Cloud Run app, and that is
the reason for the split: granular scaling and lifecycle, not a distributed monolith by fashion.

### Domain services

| Repository | Port | Responsibility |
|---|---|---|
| [`student360-gateway`](https://github.com/visionEAE/student360-gateway) | 8080 | Single entry point. Validates the user's access token, enforces coarse role→route rules, and **rewrites identity**: strips the user's token and forwards a service-to-service token plus the caller's identity as headers. Circuit breakers per downstream route with observable, section-level degradation. |
| [`student360-auth-service`](https://github.com/visionEAE/student360-auth-service) | 8081 | Custom SSO speaking the same contract an institutional IdP would (JWKS, role claims). Short-lived RS256 access tokens; opaque refresh tokens with rotation and **replay detection** (reusing a consumed refresh token revokes the entire session family). |
| [`student360-core-service`](https://github.com/visionEAE/student360-core-service) | 8082 | Simulates the SIS + ERP: identity, academic status (GPA history, current courses and grades), financial status (balance, arrears, scholarship), the professor/student directory. Source of truth for everything institutional. |
| [`student360-lms-service`](https://github.com/visionEAE/student360-lms-service) | 8083 | Simulates the learning platform: courses, submissions, access logs, and the *interpreted* engagement signal (days since last access, on-time rate, idle courses). Kept separate from the SIS/ERP because it produces high-frequency behavioural signals, not official state — and because at a real institution it is a third-party system with its own release cycle. |
| [`student360-support-service`](https://github.com/visionEAE/student360-support-service) | 8084 | Everything new: pseudonymised wellbeing entries, the convergent-risk rule, alerts, intervention plans, advisor reports and requests. The only service that calls two others synchronously and composes a decision from their answers. |
| [`student360-network-service`](https://github.com/visionEAE/student360-network-service) | 8085 | The support network: a weighted graph in **Neo4j** of who supports each student. Each `SUPPORTS` edge is rated 1–10 independently by the student and by the support team — neither rating is averaged into the other. |
| [`student360-frontend`](https://github.com/visionEAE/student360-frontend) | 5173 / 8080 | Single-page app (React + Vite, atomic design), served by nginx once containerised. Two experiences: the student's 360° view and the advisor's caseload panel. |
| [`student360-dwh-relay`](https://github.com/visionEAE/student360-dwh-relay) | — (job) | Feeds the data warehouse: drains each service's outbox table into Pub/Sub on a schedule. Exists to move at-least-once delivery logic out of every producing service and into one small, independently testable job. |

### Foundations and infrastructure

| Repository | Function |
|---|---|
| [`student360-common`](https://github.com/visionEAE/student360-common) | Shared library: the `@Audited` aspect and its JDBC writer, identity and request-correlation plumbing, the outbox publisher, JSON logging — and, centrally, the **service-token port** with two adapter pairs (local HS256 / Google-signed identity tokens) selected purely by configuration. That port is what made the cloud move a swap, not a rewrite. |
| [`student360-infra`](https://github.com/visionEAE/student360-infra) | Local orchestration (Docker Compose: Postgres + Neo4j + Adminer), seeds, demo scripts with built-in negative cases, and the cross-cutting docs. |
| [`terraform-backend`](https://github.com/visionEAE/terraform-backend) | The **irrecoverable** half of the GCP footprint: the Terraform state bucket, Artifact Registry (rollback history), Secret Manager, the keyless CI identity (Workload Identity Federation) and the BigQuery dataset. |
| [`terraform-core`](https://github.com/visionEAE/terraform-core) | The **disposable** half: the seven Cloud Run services, the relay job, Cloud SQL on a private IP, networking, the data-warehouse feed, and the bastion. Destroyable and rebuildable from zero against the backend's outputs. |
| [`workflows`](https://github.com/visionEAE/workflows) | Generic, reusable CI/CD (§5). Every other repository carries only two thin caller files; the logic lives here once. |

## 3. The gateway is self-managed, on purpose — and it is not the antipattern it looks like

Running a Spring Cloud stack on top of a platform that already does networking is a well-known
antipattern *when the framework is doing the platform's job twice*. The classic offenders —
Eureka service discovery, a Config Server, client-side load balancing — are not present here, and
were deliberately designed out: Cloud Run already gives every service a stable DNS name, load
balancing, autoscaling and revision management, so duplicating that inside the application would
mean paying for the same problem twice, with more JVMs to operate. Concretely, in this system:

| Concern | The classic (avoided) Spring Cloud answer | What this system does instead |
|---|---|---|
| Service discovery | Eureka | Deterministic `*.run.app` URLs, computed once in Terraform and injected as environment variables |
| Configuration | Config Server | Environment variables + Secret Manager |
| Load balancing | Ribbon | Cloud Run's own load balancer |
| Service-to-service auth | A shared secret | Google-signed identity tokens + IAM (`run.invoker`) |
| Reliable data delivery | A hand-rolled bus | Pub/Sub + a managed BigQuery subscription |

What *does* remain from the Spring Cloud ecosystem is the gateway itself, and it stays for a
reason that has nothing to do with network topology: it enforces **application policy** that no
managed edge product gives for free — identity rewriting (the user's token is replaced with a
service token before anything downstream sees a request), coarse role→route authorization, and
section-level degradation (a slow or failing downstream greys out one panel of the 360° view
instead of failing the whole page, via Resilience4j circuit breakers with an explicit fallback
route). That is why it was built as a **self-managed gateway from day one of local development**,
not bolted on for the cloud: it had to exist locally regardless (there is no managed edge in
Docker Compose), and having it already do identity rewriting and degradation meant stage 2 needed
zero new architecture at the edge — only new adapters behind the same ports (see §2's note on
`student360-common`) and Terraform wiring around it. The honest trade-off, made explicit rather
than hidden: a managed alternative (Google API Gateway, validating the same JWKS and calling
Cloud Run with its own service-account identity) would let the edge scale without any JVM to keep
warm, at the cost of local/cloud parity — the API Gateway product does not exist outside GCP, so
the one environment that runs identically on a laptop and in the cloud today would stop being the
same system. For a proof of concept whose local runnability is part of the deliverable, keeping
the gateway self-managed was the right side of that trade-off; it is also the piece we would
reconsider first if this system had to grow past a POC.

## 4. Why the support network is a graph, in a service of its own

"Who is this student's strongest support?" is a genuinely different question from the rest of the
platform. It is *subjective* (rated, and rated differently by the student and by the team),
*mutable*, and naturally a graph — a student's network overlaps with other students' networks, and
the interesting queries are about structure (paths, shared connections, centrality), not rows.
Modelling it as a table would force every one of those questions into a join, and the shape of the
data would stop matching the shape of the questions being asked of it. Putting it in **Neo4j**
behind its own service keeps that shape honest, and isolates it operationally: the graph store has
no managed equivalent on GCP, so it runs on Neo4j AuraDB (external, reached over
`neo4j+s://`) — the *only* thing that differs between the local and cloud deployments of this
service is that one connection string, because the port the service talks through never changed.

Two properties are worth calling out:

* **Both sides rate independently.** The same person carries up to two edges — the student's own
  rating and the support team's — and neither is averaged away into the other. A student rating
  their advisor 5/10 while the advisor rates the relationship 8/10 is a *signal*, not a conflict
  to resolve.
* **Contact details have a stated provenance.** Opening a person shows how to reach them and a
  short summary of who they are, labelled with where that information came from: `DIRECTORY`
  (resolved live from `core-service` — professors, fellow students), `SELF_REPORTED` (typed in by
  whoever added them — family, friends), or `NONE`. The institution's directory is never copied
  into the graph, so an institutional email cannot go stale, and nobody mistakes a hand-typed
  phone number for an official one.

There is also a scaling argument for why the support network — and the support service more
broadly — live apart from the institutional core: the SIS/ERP and LMS simulate systems whose real
counterparts serve an entire university and need to scale with enrolment and academic-calendar
load, largely independent of how many wellbeing entries or support-network edits are happening at
any moment. Isolating the newer, lower-traffic concerns (wellbeing, alerts, the graph) into their
own services means each one can be given exactly the scaling profile its own load justifies,
instead of everything inheriting the ceiling — or the cost — of the busiest one.

## 5. Generic, reusable CI/CD

Every service repository carries exactly two thin workflow files — `ci.yml`, `deploy.yml` — that
call into the shared [`workflows`](https://github.com/visionEAE/workflows) repository. The logic
lives once, not once per repository:

- **`java-ci.yml` / `frontend-ci.yml`** — checkout, build `student360-common` from source when a
  service needs it (mirroring the local `make build-common`), `mvn verify` or lint+build+test.
- **`java-deploy.yml` / `frontend-deploy.yml`** — a **content-hash gate** decides whether to build
  at all: the image tag is derived from what actually goes into it (sources, `pom.xml`/lockfile,
  Dockerfile, the exact `student360-common` commit, and — for the SPA — the gateway URL baked into
  the bundle at build time). If that tag already exists in Artifact Registry, nothing is rebuilt.
  Every rollout, whether freshly built or reused, deploys **by digest** — `gcloud run services
  update --image=…@sha256:…` — never by a movable tag, so a revision always names the exact bytes
  it runs and a rollback is one command with a digest copied from a previous run's summary.
- **Keyless, always.** No service-account key exists anywhere in the system. Deploy jobs trade
  GitHub's own OIDC token for short-lived Google credentials through Workload Identity Federation;
  the trust condition pins both the GitHub organisation *and* an explicit repository allowlist, so
  creating a new repository in the organisation grants it nothing by default. A manual trigger
  (`workflow_dispatch`) is always available on every deploy pipeline, independent of the push that
  would normally fire it.

Terraform owns the **shape** of each Cloud Run service (resources, probes, environment, secrets,
scaling); the pipeline owns **which build is live** — the two are deliberately kept from fighting
over the same field (`ignore_changes` on the image in Terraform), so an unrelated infrastructure
change can never silently roll a service back to an older build.

## 6. Terraform, split by how recoverable each half is

Infrastructure lives in two repositories, split by one question: *if this were destroyed, would
rebuilding it just be slow, or would something be permanently lost?*

- **[`terraform-backend`](https://github.com/visionEAE/terraform-backend)** holds what would be
  genuinely lost: the Terraform state bucket, Artifact Registry (and with it, the rollback
  history), Secret Manager, the Workload Identity Federation pool that lets CI authenticate at
  all, and the BigQuery dataset the data warehouse lands in. Applied rarely, by hand, from a
  workstation — never from CI.
- **[`terraform-core`](https://github.com/visionEAE/terraform-core)** holds everything disposable:
  the seven Cloud Run services, the relay job, Cloud SQL, the private network, and a bastion for
  one-off database access. It reads the backend's outputs through
  `data.terraform_remote_state` and can be destroyed and rebuilt from zero without losing anything
  that matters — the durable state lives one repository over.

Both are internally modular by concern rather than one flat file per repository —
`terraform-backend` factors into `project-services`, `tf-state`, `artifact-registry`, `secrets`,
`github-oidc` and `bigquery`; `terraform-core` into `network`, `cloudsql`, `service-accounts`,
`cloud-run-service` (the one module every one of the seven services instantiates, parameterised),
`cloud-run-job` and `dwh`. The Cloud Run URLs every service needs to call another are not passed
by hand or discovered at runtime: they are **deterministic** —
`https://<service>-<project-number>.<region>.run.app` — computed once as a Terraform local from
`data.google_project`, which is what lets every service receive every URL (and its own audience)
at creation time, with no apply-order cycles.

## 7. Two-layer authorization

1. **Coarse, at the gateway**: a route belongs to a set of roles (`STUDENT`, `ADVISOR`, `ADMIN`).
   A token without the right role never reaches a service — `403` before anything downstream runs.
2. **Fine-grained, inside each service**: a student may read only their own record (`ref` claim
   equals the id requested); an advisor may read only a student they hold an *active assignment*
   to. Wrong relationship → `403`, **and an audit record explaining why**, recorded before the
   response leaves.

Both layers are exercised live in the demonstration thread (§10) — locally, and again against the
deployed cloud services.

## 8. Audit trail

Every access to sensitive data — allowed or denied — writes one row to an append-only audit table:
who, what, about which student, when, under which authorization relationship (`SELF`,
`ASSIGNMENT`, `ADMIN_ROLE`, or `NONE` for a denial), and the correlation id of the request. The
database itself enforces append-only: each service's database role has `INSERT`/`SELECT` on the
table and nothing else — no application bug, and no person with a valid database credential, can
rewrite history.

A single request that crosses three services (submit a wellbeing entry → the rule calls
`core-service` and `lms-service`) leaves three correlated rows, one per service, all sharing the
same request id — reconstructible with one query.

## 9. Backend architecture: CQRS + ports and adapters

Every service separates **commands** (writes) from **queries** (reads), each handled by its own
class. Handlers depend only on interfaces (`domain/port`): a repository, a client to another
service, a clock, a service-token provider. Nothing about *how* data is stored or fetched leaks
into business logic — an interface can be swapped without touching a single handler.

This is exactly what stage 2 leaned on. The interfaces that now point at managed cloud services —
service-to-service authentication, event publishing, secret storage — already existed and were
already implemented locally in stage 1; moving to the cloud swapped the adapter behind each
interface, never the business logic that calls it. `student360-common`'s service-token port is the
clearest example: the same `ServiceTokenProvider`/`ServiceTokenValidator` interfaces are satisfied
by an HS256 adapter locally and a Google-identity-token adapter in Cloud Run, selected by one
configuration property.

## 10. The demonstration thread

The proof of concept is built to make this sequence work, live, in one run — and it has been run
successfully both locally and against the deployed Cloud Run services:

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
10. In the cloud, the same wellbeing entry additionally lands — asynchronously, via the outbox —
    in BigQuery within one scheduler cycle, without the request that created it ever waiting on it.

## 11. Frontend

A React single-page app built with **atomic design** (atoms → molecules → organisms → templates →
pages), so the same building blocks are reused across the student and advisor experiences rather
than duplicated per screen. The access token is kept in memory only (never in browser storage);
the refresh token lives in an `HttpOnly` cookie; concurrent `401`s share a single refresh attempt
so they can never look like a token replay. In production the same SPA is built once into a
multi-stage nginx image, with the gateway URL baked in at build time and served with immutable
caching on hashed assets and no caching on `index.html`.

## 12. What stage 2 delivered

Stage 1 ran entirely on a developer's machine. Stage 2 took every interface named as a future swap
and gave it a real cloud implementation — nothing described here is a plan, all of it is deployed
and was verified against the live services:

| Concern | Stage 1 (local) | Stage 2 (delivered) |
|---|---|---|
| Service-to-service auth | Locally-signed HS256 token | Google-signed identity token, validated by Cloud Run IAM and again by the application |
| Domain events | Outbox table, nothing downstream | Outbox → Cloud Run job → Pub/Sub → BigQuery subscription |
| Database | Docker Compose PostgreSQL | Cloud SQL, private IP, one schema per service, Direct VPC egress |
| Support-network store | Local Neo4j container | Neo4j AuraDB Free, same port, only the connection string changed |
| Secrets | `.env` file | Secret Manager; database passwords generated by Terraform, seed passwords fixed and stored as secrets, JWT signing key mounted as a volume |
| Compute | Docker Compose | Cloud Run, scale-to-zero except the five services kept at one warm instance to avoid cold-start/circuit-breaker interaction |
| Deployment identity | N/A | Fully keyless — Workload Identity Federation, zero service-account keys |
| Observability | JSON logs on stdout | The same JSON logs, now in Cloud Logging, still correlated by request id end to end |

Running cost at rest is a handful of dollars a month — dominated by the always-on Cloud SQL
instance — with every compute service scaling to zero or near-zero between uses.

## 13. Try it yourself

### Locally

Stage 1 runs fully offline: PostgreSQL, Neo4j and the six services in Docker Compose. Every
seeded account uses the password **`student360`**. See
[`running-locally.md`](https://github.com/visionEAE/student360-infra/blob/main/docs/running-locally.md)
for the full runbook.

### In the cloud

The stage 2 deployment is live on Cloud Run. Demo account passwords are fixed but not published
here — read them from Secret Manager
(`gcloud secrets versions access latest --secret=s360-prod-seed-student-password` /
`...-seed-staff-password`), as documented in
[`stage2-deployment.md`](stage2-deployment.md).

| Perspective | Email | What you see |
|---|---|---|
| Student — at-risk case | `maria.rojas@u.icesi.edu.co` | Own 360° view, an active high-severity alert generated against her own data, "Mi espacio seguro" wellbeing form, and a deliberately **thin** support network |
| Student — on track | `ana.torres@u.icesi.edu.co` | Own 360° view with no open alert, and the contrast case for "Mi red de apoyo": a broad, balanced network |
| Student-support team | `carlos.mejia@icesi.edu.co` | "Mis estudiantes" overview, alert inbox, interventions, reports |
| Student-support team | `diana.perez@icesi.edu.co` | A second advisor's caseload — also the one who is correctly **denied** access to María Rojas's case, since she holds no active assignment to her |

"Mi red de apoyo" is an interactive graph: drag a node, zoom, and click a person to see their
contact details, a one-line summary of who they are, and every rating on the relationship.

---

The full design rationale — creative process, architecture diagram, database model, the answers to
every part of the technical test, and the security and communication decisions summarised above —
is written up in
[`prueba-tecnica.md`](prueba-tecnica.md).
