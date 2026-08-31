# Vista 360° del Estudiante — Documento de diseño y decisiones

**Prueba técnica · Semillero — Ingeniero de Arquitectura e Innovación**
Autor: Kevin Steven Nieto Curaca · Organización: [visionEAE](https://github.com/visionEAE)

---

## 1. Introducción

Este documento acompaña la solución construida para el caso *Vista 360° del Estudiante*: qué se
diseñó, por qué, cómo se comunican sus piezas, cómo se asegura, y las respuestas argumentadas a
las partes 1–4 de la prueba.

Metodología de trabajo:

- **Proceso creativo primero, diseño top-to-bottom después**: se definió una visión y una
  pregunta reto, se filtraron ideas por impacto/viabilidad, y solo entonces se diseñó de arriba
  hacia abajo — diagrama de arquitectura, contratos de API, diagrama de base de datos,
  implementación.
- **Versionamiento**: estrategia *trunk-based* durante la construcción inicial de cada
  repositorio (commits convencionales validados por hook local de lefthook — sin gastar minutos
  de CI en ello), evolucionando a un flujo de ramas cortas + PR + *rebase-merge* una vez cada
  repo tuvo su base funcional. Un PR = una funcionalidad lógica verificada.
- **Despliegue en GCP** con Terraform, arquitectura serverless (Cloud Run) y CI/CD *keyless*.
- **Servicios institucionales simulados** por motivos de alcance: SIS/ERP y LMS se simulan
  detrás de los mismos contratos que expondrían los sistemas reales, de modo que el reemplazo es
  configuración, no rediseño (supuesto declarado, ver §4).

## 2. Proceso creativo

### Visión

Lo primero que se definió fue una visión. Inicialmente estaba enfocada en *monitorear* el
desempeño de los estudiantes; sin embargo, monitorear no es el fin último — es un medio. El fin
se transmite así:

> Sería ideal poder **intervenir oportunamente** en los aspectos económicos, emocionales y
> académicos de todos los estudiantes de la Universidad Icesi.

### Pregunta reto

> ¿Cómo podemos crear un sistema de alertas tempranas que permita al equipo de acompañamiento
> intervenir oportunamente en los aspectos emocionales, académicos y económicos de los
> estudiantes de la Universidad Icesi?

### Información relevante (investigación)

- **Factor académico**: las calificaciones finales son indicadores *forenses* (llegan tarde).
  Los predictores tempranos más efectivos son conductuales: fluctuaciones de asistencia,
  entregas tardías repetitivas y descensos drásticos de actividad en el campus virtual.
- **Factor económico**: las tensiones financieras son la causa principal del abandono
  "silencioso". Los sistemas de retención cruzan contexto socioeconómico con eventos
  detonantes: retrasos en cuotas, apoyos denegados, riesgo de perder becas por condicionamiento
  de promedio.
- **Factor emocional**: difícil de rastrear pasivamente sin vulnerar la privacidad. Las
  instituciones pioneras usan herramientas activas — *encuestas de pulso* (micro-cuestionarios
  de estado de ánimo) — y proxies de aislamiento como la desconexión abrupta de redes de apoyo.
- **Tendencias**: *triage* institucional (derivar eficientemente, no solo predecir: los vacíos
  técnicos van a pares académicos, las alertas combinadas escalan a trabajo social); sistemas
  *opt-in* con transparencia (el estudiante sabe qué datos se cruzan y puede pedir ayuda
  proactivamente, eliminando el estigma de la intervención sorpresa); y mitigación de sesgos
  algorítmicos (no etiquetar "alto riesgo" por contexto demográfico de ingreso).

### Ideación

Lluvia de ideas puntuada de 0 a 5 bajo dos criterios: realizable en el tiempo disponible e
impacto alto en los estudiantes.

| Idea | Realizable en el tiempo | Impacto alto | Total |
|---|---|---|---|
| Modelo predictivo de intervención | 1 | 5 | 6 |
| **Ruta de intervención** | 5 | 5 | **10** |
| **Red de apoyo** | 3 | 4 | **7** |
| **Rincón seguro** | 5 | 4 | **9** |

**Resumen de la idea desarrollada**: una plataforma donde estudiantes y colaboradores registran
información sobre los aspectos económicos, académicos y emocionales, de tal manera que se
activen **rutas de intervención** según las necesidades detectadas, apoyándose en la **red de
apoyo** del joven dentro de la propia universidad — con el propósito futuro de aglomerar
información para entrenar un **modelo predictivo** de intervención temprana (por eso el data
warehouse es un requisito de primera clase, no un anexo).

Las tres ideas ganadoras existen en la solución: la ruta de intervención (alertas por regla de
convergencia + planes sugeridos), el rincón seguro ("Mi espacio seguro": encuesta de pulso en
tres dimensiones, *opt-in* y transparente) y la red de apoyo (grafo ponderado en Neo4j).

## 3. Arquitectura: función de cada repositorio

El diseño de arquitectura se hizo en dos instancias. En la **primera**, antes de dibujar nada, se
fijó el entendimiento real de los servicios puestos a disposición por el enunciado y el conjunto
de premisas que se toman como verdaderas para que el sistema tenga sentido completo — están
declaradas explícitamente en el §4, precisamente para que sean auditables y no queden implícitas
en el código. En la **segunda**, con esas premisas fijas, se dibujó el diagrama de arquitectura
cloud (§3.1) que simula esos servicios y documenta las decisiones técnicas tomadas para el
desempeño de la prueba con el menor acople posible hacia un sistema de producción real — cada
pieza que en la prueba es una simulación (SIS, ERP, LMS) queda detrás de un contrato explícito,
de modo que reemplazarla en un sistema real es configuración de un adaptador, no un rediseño.

Un repositorio por unidad desplegable — cada servicio es un Cloud Run independiente, y esa es la
razón de la separación (escalamiento y ciclo de vida granulares, no monolito distribuido por
moda). El caso más claro de esa granularidad es `support-service` y `network-service`: el SIS, el
ERP y el LMS simulan sistemas cuyos equivalentes reales sirven a toda la universidad y necesitan
escalar con la matrícula y el calendario académico, en buena medida independientemente de cuántas
entradas de bienestar o ediciones de red de apoyo ocurran en un momento dado. Aislar lo nuevo y de
menor tráfico (bienestar, alertas, el grafo) en sus propios servicios permite darle a cada uno
exactamente el perfil de escalamiento que su propia carga justifica, en vez de que todo herede el
techo — o el costo — del más exigente. Es también, no accidentalmente, la separación que apunta
hacia una infraestructura 100% cloud: ninguno de estos dos servicios existe en la plataforma
on-premise que se simula (SIS/ERP/LMS), así que nacer como servicios propios, separados del core,
es coherente con que son responsabilidades nuevas de la institución, no una función que un sistema
heredado ya resolvía.

### Servicios de dominio

| Repositorio | Puerto | Función |
|---|---|---|
| [`student360-gateway`](https://github.com/visionEAE/student360-gateway) | 8080 | Punto de entrada único. Valida el token del usuario, aplica la autorización gruesa rol→ruta, **reescribe la identidad**: elimina el token del usuario y adjunta un token de servicio + la identidad validada como headers. Circuit breakers por ruta con degradación observable. |
| [`student360-auth-service`](https://github.com/visionEAE/student360-auth-service) | 8081 | SSO propio con el mismo contrato del IdP institucional (JWKS, claims de rol). Tokens de acceso RS256 de 15 min; *refresh tokens* opacos con rotación y **detección de reuso** (un replay revoca la familia de sesión completa). |
| [`student360-core-service`](https://github.com/visionEAE/student360-core-service) | 8082 | Simula SIS + ERP: identidad, estado académico (historial de promedio, materias y notas actuales), estado financiero (cuotas, mora, beca), directorio de profesores/estudiantes. Fuente de verdad de lo institucional. |
| [`student360-lms-service`](https://github.com/visionEAE/student360-lms-service) | 8083 | Simula el campus virtual: cursos, entregas, accesos, y la **señal interpretada** de engagement (días sin ingresar, tasa de entregas a tiempo, cursos inactivos). Separado del core porque produce señales conductuales de alta frecuencia, no estado oficial — y porque en la realidad es un tercero con su propio ciclo de vida. |
| [`student360-support-service`](https://github.com/visionEAE/student360-support-service) | 8084 | **Todo lo nuevo**: registros de bienestar (pseudonimizados por HMAC), la regla de riesgo convergente, alertas, planes de intervención, reportes y solicitudes del equipo de acompañamiento. Es el único servicio que llama a otros dos de forma síncrona y compone una decisión. |
| [`student360-network-service`](https://github.com/visionEAE/student360-network-service) | 8085 | La red de apoyo: grafo ponderado en **Neo4j** de quién apoya a cada estudiante. Cada arista `SUPPORTS` la califican (1–10) independientemente el estudiante y el equipo — ninguna opinión promedia a la otra. Grafo porque la pregunta es estructural y subjetiva, no una tabla de join. |
| [`student360-frontend`](https://github.com/visionEAE/student360-frontend) | 5173/8080 | SPA (React + Vite, atomic design) servida por nginx en Cloud Run. Dos experiencias: la vista 360° del estudiante y el panel del equipo de acompañamiento. |
| [`student360-dwh-relay`](https://github.com/visionEAE/student360-dwh-relay) | job | Alimenta el data warehouse: drena las tablas *outbox* hacia Pub/Sub (ver §5). |

Sobre el gateway: mantener un componente Spring Cloud propio encima de Cloud Run puede leerse como
antipatrón — la plataforma ya resuelve descubrimiento, balanceo y escalado, y de hecho el resto
del sistema evita duplicar exactamente eso (sin Eureka, sin Config Server, sin balanceo propio).
Lo que el gateway conserva no es topología de red sino **política de aplicación** — reescritura de
identidad y degradación observable por sección — que ningún borde gestionado da gratis, y que tuvo
que existir desde el desarrollo local (no hay borde gestionado en Docker Compose), por lo que la
etapa 2 no exigió arquitectura nueva ahí, solo adaptadores nuevos detrás de los mismos puertos. El
argumento completo, con la alternativa considerada (Google API Gateway) y el trade-off explícito
frente a la paridad local/nube, está en el
[OVERVIEW de la organización, §3](OVERVIEW.md#3-the-gateway-is-self-managed-on-purpose--and-it-is-not-the-antipattern-it-looks-like).

### Fundaciones e infraestructura

| Repositorio | Función |
|---|---|
| [`student360-common`](https://github.com/visionEAE/student360-common) | Biblioteca compartida: auditoría (aspecto `@Audited` + escritor JDBC), identidad y correlación, puertos de tokens de servicio con **dos pares de adaptadores** (HS256 local / ID tokens de Google), publicador outbox, logging JSON. Los puertos son el mecanismo que hizo del paso a la nube un cambio de adaptadores y no un rediseño. |
| [`student360-infra`](https://github.com/visionEAE/student360-infra) | Orquestación local (docker-compose: Postgres + Neo4j + Adminer), Makefile, seeds, scripts de demostración con casos negativos, y toda la documentación transversal (`docs/`). |
| [`terraform-backend`](https://github.com/visionEAE/terraform-backend) | La mitad **irrecuperable** de la infra GCP: bucket de estado de Terraform, Artifact Registry (historial de rollback), Secret Manager, la identidad keyless de CI (WIF) y el dataset de BigQuery. Regla de separación: *si esto se destruyera, ¿reconstruirlo sería solo lento, o se perdería algo?* |
| [`terraform-core`](https://github.com/visionEAE/terraform-core) | La mitad **desechable**: los 7 servicios Cloud Run + el job relay, Cloud SQL (IP privada), networking, el feed del DWH y el bastión. Destruible y reconstruible desde cero contra los outputs del backend. |
| [`workflows`](https://github.com/visionEAE/workflows) | CI/CD genérico reutilizable: verificación, build con *gate por hash de contenido* y despliegue por *digest* (§5.3). Cada repo solo lleva dos *callers* delgados. |

### 3.1 Diagrama de arquitectura (GCP)

```mermaid
flowchart TB
    subgraph usuarios [" "]
        EST["👤 Estudiante"]
        ACOMP["👥 Equipo de acompañamiento"]
    end

    subgraph publico ["Cloud Run — públicos"]
        WEB["s360-web<br/>(nginx + SPA)"]
        GW["s360-gateway<br/>autorización gruesa,<br/>reescritura de identidad"]
        AUTH["s360-auth<br/>SSO · JWKS · refresh rotation"]
    end

    subgraph privado ["Cloud Run — privados (solo IAM, ID tokens de Google)"]
        CORE["s360-core<br/>SIS + ERP"]
        LMS["s360-lms<br/>campus virtual"]
        SUP["s360-support<br/>alertas · rutas · bienestar"]
        NET["s360-network<br/>red de apoyo"]
    end

    subgraph datos ["Datos"]
        SQL[("Cloud SQL PG16<br/>IP privada<br/>1 schema por servicio<br/>+ audit append-only")]
        AURA[("Neo4j AuraDB Free<br/>grafo SUPPORTS")]
    end

    subgraph dwh ["Feed del data warehouse (serverless)"]
        RELAY["s360-relay<br/>Cloud Run Job<br/>(Scheduler c/5 min)"]
        PS["Pub/Sub<br/>student360-events"]
        BQ[("BigQuery<br/>student360_dwh")]
    end

    EST & ACOMP --> WEB
    WEB -->|"HTTPS + JWT usuario"| GW
    GW -->|"login / JWKS"| AUTH
    GW -->|"ID token Google"| CORE & LMS & SUP & NET
    SUP -->|"señales síncronas"| CORE & LMS
    NET -->|"directorio"| CORE
    AUTH & CORE & LMS & SUP & NET -->|"VPC egress directo"| SQL
    NET -->|"neo4j+s://"| AURA
    SUP & NET -.->|"outbox (misma tx)"| SQL
    RELAY -->|"drena outbox"| SQL
    RELAY --> PS
    PS -->|"BigQuery subscription"| BQ

    subgraph ci ["CI/CD keyless"]
        GH["GitHub Actions<br/>OIDC → WIF<br/>(sin llaves)"]
        AR["Artifact Registry<br/>tags content-hash<br/>rollout por digest"]
    end
    GH --> AR
    GH -.->|"gcloud run update @digest"| publico & privado
```

### 3.2 Diagrama de datos

Una sola instancia de PostgreSQL, **un schema por servicio**, y un rol de base de datos confinado
a su propio schema — el aislamiento no es convención, lo hace cumplir el motor. `audit` es el
único schema que ningún servicio posee: todos escriben en él por `INSERT`, nadie puede `UPDATE`
ni `DELETE`. La red de apoyo vive en un motor distinto porque su forma es distinta (§3, servicio
de networking).

```mermaid
flowchart LR
    subgraph pg ["Cloud SQL — una instancia PostgreSQL 16"]
        direction TB
        S_AUTH["schema auth<br/>usuarios · refresh_token"]
        S_CORE["schema core<br/>student · program · enrollment<br/>course_grade · professor"]
        S_LMS["schema lms<br/>course · submission · access_log"]
        S_SUP["schema support<br/>wellbeing_entry · alert<br/>intervention_plan · outbox_event"]
        S_NET["schema network<br/>(metadatos · outbox_event)"]
        S_AUDIT[("schema audit<br/>audit_record<br/>INSERT/SELECT only — sin dueño")]
    end
    AUTH_SVC["auth-service"] -->|"rol confinado"| S_AUTH
    CORE_SVC["core-service"] -->|"rol confinado"| S_CORE
    LMS_SVC["lms-service"] -->|"rol confinado"| S_LMS
    SUP_SVC["support-service"] -->|"rol confinado"| S_SUP
    NET_SVC["network-service"] -->|"rol confinado"| S_NET
    AUTH_SVC & CORE_SVC & LMS_SVC & SUP_SVC & NET_SVC -.->|"INSERT/SELECT"| S_AUDIT
    NET_SVC ==>|"grafo SUPPORTS<br/>(1–10, por ambos lados)"| NEO[("Neo4j<br/>Person · Student —SUPPORTS→")]
```

**Diagrama interactivo (dbdiagram.io)**: [dbdiagram.io/d/vista360](https://dbdiagram.io/d/vista360-69876916bd82f5fce2f9f477)
— generado a partir de las migraciones Flyway reales de cada servicio (una tabla por cada
`CREATE TABLE`, con sus PK/FK, `UNIQUE` y `CHECK` reales; las columnas `*_reference` /
`*_pseudonym` que "apuntan" a otro schema están marcadas explícitamente como **clave
cross-service, no FK de base de datos** — ningún servicio comparte schema con otro, así que
ninguna de esas columnas es en realidad una foreign key en Postgres). Fuente DBML, para
copiar y pegar directo en <https://dbdiagram.io>:

```dbml
Project vista360 {
  database_type: 'PostgreSQL'
  Note: '''
  Vista 360° del Estudiante — una instancia PostgreSQL 16, un schema por servicio, un rol de base
  de datos confinado a su propio schema (make check-isolation lo prueba en local; Cloud SQL lleva
  el mismo modelo a producción, ver stage2-deployment.md §5). Las columnas *_reference /
  *_pseudonym que "apuntan" a una entidad de otro schema son CLAVES CROSS-SERVICE, no foreign
  keys: los servicios nunca comparten schema ni hacen join entre ellos — ese límite lo impone el
  rol de base de datos, no solo la convención.

  NO representado aquí: la red de apoyo (quién apoya a cada estudiante) vive en Neo4j, no en
  Postgres, porque es un grafo, no una tabla — ver el Note "graph_store" al final de este script,
  y prueba-tecnica.md §3 / OVERVIEW.md §4 para el porqué.
  '''
}

// ─────────────────────────── auth ───────────────────────────
Table auth.app_user {
  id uuid [pk]
  email varchar [unique, not null]
  password_hash varchar [not null, note: 'BCrypt; never logged']
  full_name varchar
  external_reference varchar [note: 'cross-service key (S-1001…) — matches core.student.id or an advisor id; NOT a DB foreign key']
  active boolean [not null, default: true]
  created_at timestamp [not null]
}

Table auth.role {
  id int [pk, increment]
  name varchar [unique, not null, note: 'STUDENT | ADVISOR | ADMIN']
}

Table auth.user_role {
  user_id uuid [ref: > auth.app_user.id, not null]
  role_id int [ref: > auth.role.id, not null]

  indexes {
    (user_id, role_id) [pk]
  }
}

Table auth.auth_session {
  id uuid [pk]
  user_id uuid [ref: > auth.app_user.id, not null]
  created_at timestamp [not null]
  revoked_at timestamp
  revocation_reason varchar [note: 'LOGOUT | REUSE_DETECTED | EXPIRED']
  user_agent varchar
  source_ip varchar
  Note: 'A session is a refresh-token FAMILY: every rotation stays inside it, and reuse revokes the whole family.'
}

Table auth.refresh_token {
  id uuid [pk]
  session_id uuid [ref: > auth.auth_session.id, not null]
  token_hash varchar [unique, not null, note: 'SHA-256 of the opaque value; the value itself is never stored']
  issued_at timestamp [not null]
  expires_at timestamp [not null]
  used_at timestamp
  replaced_by uuid [ref: > auth.refresh_token.id]
}

// ─────────────────────────── core ───────────────────────────
Table core.program {
  id int [pk, increment]
  code varchar [unique, not null]
  name varchar [not null]
  faculty varchar [not null]
  total_semesters int [not null, default: 10]
}

Table core.student {
  id varchar [pk, note: 'external id, e.g. S-1001 — the cross-service key every other schema references informally']
  code varchar
  first_name varchar [not null]
  last_name varchar [not null]
  email varchar [unique, not null]
  program_id int [ref: > core.program.id, not null]
  admission_term varchar [not null]
  current_semester int [not null, default: 1]
  status varchar [not null, note: 'ACTIVE | ON_LEAVE | WITHDRAWN']
  created_at timestamp [not null]
}

Table core.enrollment {
  id bigint [pk, increment]
  student_id varchar [ref: > core.student.id, not null]
  term varchar [not null]
  semester_number int
  credits_enrolled int [not null]
  credits_approved int [not null]
  term_gpa decimal(3,2) [note: 'null while the term is in progress']
  cumulative_gpa decimal(3,2) [not null]
  academic_standing varchar [not null, note: 'GOOD | PROBATION | AT_RISK']

  indexes {
    (student_id, term) [unique]
  }
}

Table core.financial_status {
  id bigint [pk, increment]
  student_id varchar [ref: > core.student.id, unique, not null]
  outstanding_balance decimal(12,2) [not null]
  overdue_balance decimal(12,2) [not null]
  days_overdue int [not null]
  tuition_amount decimal(12,2) [not null, default: 0]
  paid_amount decimal(12,2) [not null, default: 0]
  due_date date
  payment_plan varchar [note: 'short description; null = none active']
  scholarship varchar [note: 'null = none']
  financial_hold boolean [not null]
  updated_at timestamp [not null]
}

Table core.course_grade {
  id bigint [pk, increment]
  student_id varchar [ref: > core.student.id, not null]
  term varchar [not null]
  course_code varchar [not null]
  course_name varchar [not null]
  credits int [not null]
  current_grade decimal(3,2) [note: 'null until something is graded']

  indexes {
    (student_id, term, course_code) [unique]
  }
}

Table core.tuition_payment {
  id bigint [pk, increment]
  student_id varchar [ref: > core.student.id, not null]
  due_date date [not null]
  paid_at date
  description varchar [not null]
  amount decimal(12,2) [not null]
  status varchar [not null, note: 'PAID | PENDING | OVERDUE']
}

Table core.professor {
  id bigint [pk, increment]
  full_name varchar [not null]
  email varchar
  department varchar
}

Table core.course_offering {
  id bigint [pk, increment]
  term varchar [not null]
  course_code varchar [not null]
  course_name varchar [not null]
  professor_id bigint [ref: > core.professor.id, not null]

  indexes {
    (term, course_code) [unique]
  }
}

// ─────────────────────────── lms ───────────────────────────
Table lms.course {
  id int [pk, increment]
  code varchar [not null]
  name varchar [not null]
  term varchar [not null]

  indexes {
    (code, term) [unique]
  }
}

Table lms.course_enrollment {
  id int [pk, increment]
  student_reference varchar [not null, note: 'cross-service key (S-1001…) issued by core-service; NOT a DB foreign key — lms never joins to core']
  course_id int [ref: > lms.course.id, not null]
  status varchar [not null, note: 'ACTIVE | DROPPED']

  indexes {
    (student_reference, course_id) [unique]
  }
}

Table lms.assignment {
  id int [pk, increment]
  course_id int [ref: > lms.course.id, not null]
  title varchar [not null]
  type varchar [not null, note: 'HOMEWORK | QUIZ | PROJECT | EXAM']
  due_at timestamp [not null]
}

Table lms.submission {
  id int [pk, increment]
  assignment_id int [ref: > lms.assignment.id, not null]
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  submitted_at timestamp [note: 'null when MISSING — absence is a fact, not an inference']
  status varchar [not null, note: 'ON_TIME | LATE | MISSING']

  indexes {
    (assignment_id, student_reference) [unique]
  }
}

Table lms.access_log {
  id bigint [pk, increment]
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  course_id int [ref: > lms.course.id, not null]
  occurred_at timestamp [not null]
  access_type varchar [not null, note: 'LOGIN | CONTENT_VIEW | FORUM_POST | SUBMISSION']
  Note: 'High-frequency, append-only behavioural data — the signal the support rule reads.'
}

// ─────────────────────────── support ───────────────────────────
Table support.wellbeing_entry {
  id uuid [pk]
  student_pseudonym varchar [not null, note: 'HMAC(student id); the plain id never touches this table']
  status varchar [not null, default: 'SENT', note: 'DRAFT | SENT — a draft is invisible to advisors and never evaluated']
  level smallint [not null, note: '1..4, overall']
  recorded_at timestamp [not null]
  sent_at timestamp
  updated_at timestamp [not null]
}

Table support.wellbeing_entry_dimension {
  id bigint [pk, increment]
  entry_id uuid [ref: > support.wellbeing_entry.id, not null]
  dimension varchar [not null, note: 'ECONOMIC | ACADEMIC | EMOTIONAL']
  mood smallint [not null, note: '1 DIFFICULT .. 4 VERY_GOOD']
  needs varchar [note: 'text array of requested support types']
  note varchar [note: 'free text; never logged nor published']

  indexes {
    (entry_id, dimension) [unique]
  }
}

Table support.advisor_assignment {
  id int [pk, increment]
  advisor_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  valid_from date [not null]
  valid_to date [note: 'null = open-ended — the relationship that authorizes an advisor to see a student']
}

Table support.alert {
  id uuid [pk]
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  severity varchar [not null, note: 'MEDIUM | HIGH']
  source varchar [not null, note: 'which rule produced it']
  triggering_signals jsonb [not null, note: 'why it fired — explainable, not a black box']
  created_by varchar [note: 'advisor reference for manual alerts, null for the rule']
  generated_at timestamp [not null]
  updated_at timestamp [not null]
  status varchar [not null, note: 'OPEN | ACKNOWLEDGED | CLOSED']
}

Table support.intervention_plan {
  id uuid [pk]
  alert_id uuid [ref: > support.alert.id, note: 'nullable — a plan may exist without an alert']
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  type varchar [not null, note: 'ACADEMIC_FOLLOW_UP | INTEGRAL_SUPPORT']
  description varchar [not null]
  status varchar [not null, note: 'PROPOSED | ACTIVE | COMPLETED']
  created_by varchar
  created_at timestamp [not null]
  updated_at timestamp [not null]
}

Table support.support_report {
  id uuid [pk]
  alert_id uuid [ref: > support.alert.id, not null]
  advisor_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  content varchar [not null]
  created_at timestamp [not null]
}

Table support.support_request {
  id uuid [pk]
  student_reference varchar [not null, note: 'cross-service key; NOT a DB foreign key']
  alert_id uuid [ref: > support.alert.id]
  type varchar [not null, note: 'FINANCIAL_WELLBEING_REFERRAL | PSYCHOLOGICAL_SUPPORT_REFERRAL | TUTORING | WORKLOAD_ADJUSTMENT | PROFESSOR_MEETING | OTHER']
  description varchar [not null]
  status varchar [not null, note: 'OPEN | IN_PROGRESS | RESOLVED']
  resolution varchar
  created_by varchar [not null, note: 'advisor reference']
  created_at timestamp [not null]
  updated_at timestamp [not null]
}

Table support.outbox_event {
  id uuid [pk]
  event_type varchar [not null]
  aggregate_type varchar [not null]
  aggregate_id varchar [not null]
  payload jsonb [not null]
  created_at timestamp [not null]
  published_at timestamp [note: 'set by the relay job once Pub/Sub confirms the publish; null = pending drain']
}

// ─────────────────────────── network ───────────────────────────
Table network.outbox_event {
  id uuid [pk]
  event_type varchar [not null]
  aggregate_type varchar [not null]
  aggregate_id varchar [not null]
  payload jsonb [not null]
  created_at timestamp [not null]
  published_at timestamp
  Note: 'Same shape as support.outbox_event. The graph itself is NOT here — see Note "graph_store" below.'
}

// ─────────────────────────── audit (owned by no service) ───────────────────────────
Table audit.audit_record {
  id bigint [pk, increment]
  occurred_at timestamp [not null]
  request_id varchar [not null]
  trace_id varchar
  service_name varchar [not null, note: 'which service wrote it']
  record_type varchar [not null, note: 'DATA_ACCESS | SECURITY | STATE_CHANGE']
  action varchar [not null, note: 'READ_FINANCIAL_STATUS, LOGIN_FAILED, …']
  actor_id uuid
  actor_roles varchar [note: 'text array of roles']
  subject_type varchar [note: 'STUDENT | SESSION | ALERT']
  subject_id varchar
  authorization_basis varchar [note: 'SELF | ASSIGNMENT | ADMIN_ROLE | NONE']
  outcome varchar [not null, note: 'ALLOWED | DENIED']
  source_ip varchar
  details jsonb [note: 'extra context; never sensitive values in clear text']

  Note: 'Owned by NO service. Every service role has INSERT/SELECT ONLY here — enforced by GRANT, not application code. This table is the schema-per-service isolation boundary made visible.'
}

Note graph_store {
  '''
  Neo4j AuraDB Free — network-service's real data store, not representable as a relational
  table, so it is not one of the tables above:

    (:Student {reference})-[:SUPPORTS {rating: int, ratedBy: 'STUDENT' | 'TEAM'}]->(:Person {name, contactProvenance})

  Each SUPPORTS edge is rated 1-10 INDEPENDENTLY by the student and by the support team; neither
  rating is averaged into the other. contactProvenance is DIRECTORY (resolved live from
  core-service) | SELF_REPORTED | NONE. See prueba-tecnica.md §3 and OVERVIEW.md §4.
  '''
}
```

## 4. Supuestos declarados

1. **SIS, ERP y LMS se simulan** exponiendo el contrato que los sistemas reales expondrían a
   través de la plataforma de integración institucional (que no se construye: es una caja en el
   diagrama — traducción de protocolos, throttling, frontera de diagnóstico).
2. **El SSO es propio pero con el contrato del IdP institucional** (JWKS, claims): reemplazarlo
   es una propiedad del gateway, no un cambio de código.
3. **Una instancia PostgreSQL, un schema por servicio, un rol confinado por schema** —
   verificable (`make check-isolation` prueba las operaciones prohibidas y afirma que fallan).
4. **GCP no tiene grafo gestionado**: Neo4j corre en AuraDB Free (externo, `neo4j+s://`), y esa
   es la única diferencia con el Neo4j local.
5. **Los eventos de dominio se persisten primero** (patrón outbox, en la transacción del
   negocio) y se publican después: el sistema funciona completo sin el warehouse, y el warehouse
   nunca pierde lo ocurrido mientras estuvo desconectado.

## 5. Comunicación y orquestación de servicios

### 5.1 El camino de una petición (síncrono)

La SPA habla **solo con el gateway**. En cada llamada: el gateway valida el JWT del usuario
contra el JWKS del SSO, aplica la regla gruesa (¿puede este *rol* llegar a esta familia de
rutas?), y reenvía **reescribiendo la identidad** — el token del usuario nunca viaja más allá:
el servicio destino recibe un token de servicio (audiencia = ese servicio) más la identidad
validada como headers (`X-User-Id`, `X-User-Roles`, `X-External-Reference`) y el `X-Request-Id`
que correlaciona todo el recorrido.

Solo **support-service compone**: registrar un pulso de bienestar dispara síncronamente la
lectura del estado financiero (core) y la señal de engagement (lms), evalúa la regla de riesgo
sobre las tres dimensiones y genera la alerta con su ruta de intervención sugerida. Todos los
demás responden desde su propio almacén. Las fuentes caídas **degradan por sección** (circuit
breaker + fallback observable), nunca tumban la vista completa.

En la nube no hay ciclos de configuración: las URL de Cloud Run son determinísticas
(`https://<servicio>-<nº proyecto>.<región>.run.app`) y se calculan en Terraform, así que el
gateway recibe sus cinco URLs — y cada servicio su propia audiencia — **al crearse**.

### 5.2 Eventos y data warehouse (asíncrono)

Cada cambio de estado relevante escribe su evento en la tabla `outbox_event` del propio schema,
**en la misma transacción del negocio** — o se confirman juntos o se revierten juntos. El job
`s360-relay` (Cloud Scheduler, cada 5 min) drena las tablas con `FOR UPDATE SKIP LOCKED`
(ejecuciones solapadas se saltan mutuamente en vez de bloquear o duplicar), publica el envelope
textual a Pub/Sub y marca `published_at` solo tras el *ack* del broker. Entrega *at-least-once*;
deduplicación en BigQuery por el `eventId` del envelope. La *BigQuery subscription* aterriza
cada mensaje en `student360_dwh.outbox_events` sin una línea de código consumidor.

### 5.3 Orquestación de despliegues

Los pipelines (repo `workflows`) hacen dos cosas distintas con dos identificadores distintos:

- **Hash de contenido como gate de build**: el tag de la imagen se deriva de lo que realmente
  entra en ella (fuentes, pom/lockfile, Dockerfile, el commit exacto de `student360-common` — y
  para la SPA, la URL del gateway, que Vite hornea en el bundle). Si ese tag ya existe en el
  registry, no se construye nada: se reutiliza el digest.
- **Digest como unidad de rollout**: un tag se puede mover; un digest no. Toda revisión nombra
  exactamente los bytes que ejecuta y el rollback es un comando con un digest leído del resumen
  de un run anterior.

Terraform es dueño de la *forma* de cada servicio; el pipeline es dueño de *qué build está vivo*
(`ignore_changes` sobre la imagen). El trigger manual está siempre disponible.

## 6. Seguridad clave

**Autenticación de personas.** SSO con tokens de acceso RS256 de 15 minutos (claims: `roles`,
`ref`, `sid`, `jti`) y refresh tokens opacos (hash SHA-256 en base) con **rotación y detección
de reuso**: presentar un refresh ya consumido revoca la familia de sesión completa y queda
auditado como evento de seguridad. Rate-limit de login.

**Autorización en dos capas, a propósito.** El gateway responde la pregunta gruesa (¿puede un
`STUDENT` llegar a `/api/support/advisors/**`? → no). La pregunta fina — ¿puede *este*
acompañante ver a *ese* estudiante? — se decide **dentro del servicio dueño del dato**, que es
también donde se audita, registrando la *base* de la decisión: `SELF`, `ASSIGNMENT`,
`STAFF_ROLE`, `ADMIN_ROLE` o `NONE`. Un estudiante solo se ve a sí mismo; un acompañante solo a
sus asignados vigentes (la asignación se verifica contra datos, no contra el rol).

**Servicios entre sí.** Detrás de dos puertos (`ServiceTokenProvider`/`Validator`) hay dos pares
de adaptadores seleccionados por configuración: en local, HS256 con secreto compartido; en
producción, **ID tokens firmados por Google** — los servicios internos son privados por IAM
(solo las service accounts listadas como invokers pueden llamarlos), Cloud Run valida el token
en la plataforma y la aplicación lo vuelve a validar (defensa en profundidad) extrayendo la
identidad del llamador. El secreto compartido **no existe** en producción.

**CI/CD keyless.** Ninguna llave de service account existe en ningún lugar: GitHub Actions
intercambia su token OIDC por credenciales efímeras vía Workload Identity Federation, con una
condición que fija **dueño + allowlist explícita de repositorios** (cualquier repo creable en la
organización no debe heredar derechos de despliegue). El deployer es *writer* del registry —
nunca admin: ningún pipeline puede borrar el historial de rollback — y `run.developer` por
servicio — nunca `run.admin`: ningún pipeline puede reescribir el IAM de un servicio.

**Secretos y datos sensibles.** Todo secreto vive en Secret Manager (contraseñas de BD
generadas por Terraform y rotables fuera de él; llave JWT montada como volumen; credenciales de
AuraDB suministradas fuera del estado). Los registros de bienestar se **pseudonimizan** con HMAC
antes de persistir — el id del estudiante nunca acompaña al contenido sensible.

**Auditoría append-only.** Tabla `audit.audit_record` en un schema que **ningún servicio posee**;
los grants permiten solo `INSERT` y `SELECT` — el motor, no el código, garantiza que nadie
(incluido quien escribió el registro) puede alterarla. Cada registro lleva actor, acción,
sujeto, resultado, base de autorización, `request_id` y `trace_id`.

## 7. Respuestas a las preguntas de la prueba

### Parte 1 — Diseño: de dónde sale cada dato y por qué

| Dato | Fuente | Por qué así |
|---|---|---|
| Información personal, académica y financiera | `core-service` (SIS+ERP simulados) | Es estado *oficial*: una sola fuente de verdad institucional, consultada en vivo — copiarla crearía el problema de sincronización que la prueba no pide resolver |
| Actividad en el campus virtual | `lms-service` | Señal conductual de alta frecuencia, *interpretada* (días sin ingresar, % a tiempo) — separada del estado oficial porque su naturaleza, volumen y dueño real son otros |
| Reportes, alertas, solicitudes, bienestar | `support-service` (schema propio) | **Son registros nuevos que no existen en ningún sistema**: nacen aquí, con su propia base de datos, su regla de riesgo y su auditoría |
| Red de apoyo (quién apoya a quién, con qué fuerza) | `network-service` (Neo4j) + directorio de `core` | Relación subjetiva, mutable y estructural → grafo; los datos de contacto institucionales se resuelven del directorio **en tiempo de lectura** (nunca se copian: no pueden quedar obsoletos) |
| Data warehouse | outbox → relay → Pub/Sub → BigQuery | El evento se persiste con el negocio (transaccional) y se publica después: el DWH puede caerse sin perder nada y sin frenar la operación |

La comunicación entre componentes es el §5; el diagrama, el §3.1.

### Parte 2 — Servicio: materias matriculadas y notas actuales

Implementado en `student360-core-service` como parte del contrato v2:

**Contrato** — `GET /api/core/students/{id}/academic-status` (a través del gateway, con el token
del usuario). Devuelve, entre otros: `currentTerm`, `academicStanding`, `cumulativeGpa`,
`gpaHistory[]` y **`currentCourses[]`** — `{code, name, credits, currentGrade}` por cada materia
inscrita en el período actual. `404` si el estudiante no existe (solo para staff — un estudiante
no autorizado recibe `403` *antes* de la comprobación de existencia, para no filtrar existencia).

**Base de datos** (schema `core`, migrada por Flyway, versiones inmutables):
`student` (id externo `S-1001` como llave cross-service, código institucional, programa),
`program`, `enrollment` (término, créditos, promedio del término y acumulado, *standing*),
`course_grade` (estudiante, término, materia, créditos, nota acumulada actual),
`professor` y `course_offering` (quién dicta qué, por término).

**Implementación**: Java 21 / Spring Boot, CQRS (`FindAcademicStatusQuery` → handler → modelo de
lectura con la forma exacta del contrato), autorización fina antes de la existencia, acceso
auditado con base `SELF`/`STAFF_ROLE`. Verificado por tests de integración con Testcontainers
(estudiante ve lo suyo; el ajeno → 403 auditado como DENIED; staff ve todo).

### Parte 3.1 — Seguridad

Respondida en profundidad en el §6. En síntesis: SSO con rotación y detección de reuso;
autorización en **dos capas** (gruesa en el gateway por rol→ruta; fina en el servicio dueño del
dato, verificando `SELF` o asignación vigente, auditada con su base); el token del usuario nunca
pasa del gateway; servicio-a-servicio con ID tokens de Google sobre servicios privados por IAM
(HS256 solo en local, detrás de los mismos puertos); y CI keyless por WIF.

### Parte 3.2 — Comunicación

**Escenario A (estado financiero inmediato): síncrono, en vivo, con degradación.** La consulta
va SPA → gateway → `core-service`, que responde desde la fuente de verdad. Se resolvió síncrono
porque el usuario está esperando y el dato debe ser el *actual* (una copia local introduce el
problema de "¿qué tan fresco?" sin necesidad). El costo del síncrono se paga con: circuit
breaker por ruta (solo transporte y 5xx lo abren — un 4xx es una respuesta, no una falla),
timeout corto, y **degradación por sección**: si el ERP no responde, la tarjeta financiera
muestra "no disponible" con su request id, y el resto de la vista carga.

**Escenario B (cambia la condición académica → procesos + DWH): evento persistido primero.**
El cambio escribe su evento en el outbox **dentro de la misma transacción** del cambio — jamás
puede existir el cambio sin su evento ni el evento sin su cambio. De ahí, dos caminos:
(1) la reacción *temprana* de la plataforma es la regla de riesgo de `support-service`, que
evalúa las señales convergentes y levanta la alerta con ruta de intervención;
(2) hacia otros procesos y el warehouse, el relay publica el envelope a Pub/Sub — cualquier
proceso futuro se suscribe al topic sin tocar a los productores, y la BigQuery subscription
alimenta el DWH sin código. Se eligió *outbox + broker* sobre llamadas directas porque
desacopla la disponibilidad (el productor nunca espera al consumidor), garantiza no perder
eventos y deja el envelope exacto listo para *n* consumidores.

### Parte 4 — Operación y calidad

**Escenario A (información académica que a veces no carga).** Cómo lo afrontaría con lo que la
solución ya tiene previsto: (1) pedir a un director el **request id** que la UI muestra junto a
cada sección degradada; (2) con él, reconstruir el recorrido completo — el id se propaga del SPA
al último servicio y aparece en los logs JSON (Cloud Logging) y en la traza W3C de cada salto;
(3) mirar el estado del **circuit breaker** de la ruta core (`/actuator/health` lo expone): un
breaker abriéndose intermitentemente delata timeouts o 5xx del origen; (4) correlacionar con la
tabla de auditoría (`SELECT … WHERE request_id = …`), que dice qué servicio respondió y cuál
no llegó a escribir. Lo *previsto desde el diseño* que lo hace posible: request id end-to-end,
logs estructurados, trazas, breakers con salud observable, degradación por sección (el síntoma
"no carga a veces" es exactamente el fallback haciéndose visible en vez de un error opaco), y
tests de resiliencia que ya ensayan la fuente caída.

**Escenario B (reclamo: "alguien consultó o alteró mi información").** La respuesta certera
sale de la **auditoría append-only**: cada acceso a datos de un estudiante quedó registrado con
actor, acción, sujeto, resultado (`ALLOWED`/`DENIED`) y **base de autorización** — de modo que
la institución puede responder no solo *quién accedió*, sino *con qué derecho* (era el propio
estudiante; era su acompañante asignado; o fue denegado). Que el registro sea inalterable no es
política sino motor: el schema `audit` no lo posee ningún servicio y los grants no incluyen
`UPDATE`/`DELETE` — ni siquiera quien escribió el registro puede tocarlo, lo que le da valor
probatorio frente al reclamo. La consulta es directa:
`SELECT * FROM audit.audit_record WHERE subject_id = 'S-…' ORDER BY occurred_at`. Y "alterado"
tiene doble verificación: los cambios de estado son eventos auditados (`STATE_CHANGE`) y además
quedaron en el outbox con su envelope completo.

## 8. Declaración de uso de IA

Se usó **Claude Code** (Anthropic) como herramienta de desarrollo asistido durante toda la
construcción: exploración y diseño de la arquitectura, implementación de los servicios y de la
infraestructura como código, escritura y ejecución de tests, verificación en navegador real de
los flujos, redacción de documentación, y operación del despliegue en GCP. Las decisiones de
producto y arquitectura (visión, ideación, selección de ideas, separación de repositorios,
elección de grafo para la red de apoyo, estrategia de despliegue) fueron dirigidas por el autor;
la herramienta ejecutó, propuso alternativas con trade-offs y verificó cada cambio con tests
antes de integrarlo.

## 9. Entregables

| Parte | Dónde |
|---|---|
| 1 · Diagrama + decisiones | Este documento (§3.1–3.2 diagramas, §4–§6 decisiones y supuestos) |
| 2 · Servicio: materias y notas | §7, Parte 2 de este documento |
| 3 · Seguridad y comunicación | §7, Parte 3.1–3.2 de este documento |
| 4 · Operación y calidad (escenarios) | §7, Parte 4 de este documento |
| Ejecución local | [`running-locally.md`](https://github.com/visionEAE/student360-infra/blob/main/docs/running-locally.md) — credenciales demo incluidas |
| Despliegue GCP | [`stage2-deployment.md`](stage2-deployment.md) |
| Visión pública del sistema | [OVERVIEW de la organización](OVERVIEW.md) |
