# CLAUDE.md — GTM Offerings

!include AGENTS.md §2 (Coding Agents & Workflow Architecture)

## 🚨 CRITICAL ARCHITECTURE RULE (READ FIRST)

- **MULTI-AGENT PROTOCOL:** Before reading further or executing ANY commands, you must fully load and abide by the multi-agent role lifecycle (BA → Architect → Developer → QA) and the **Git Worktree Isolation workflow** defined in `AGENTS.md` (§2).
- **WORKSPACE RESTRICTION:** You are forbidden from writing code or running executions directly inside the main repository workspace unless explicitly instructed by the Technical Architect Agent.

---

## 1. Project Overview & Personas

GTM Offerings is a Salesforce Lightning/Apex application built to simplify, standardize, and score Go-To-Market strategy across all Publicis Sapient Salesforce Offerings. It consists of the **GTM Offerings App** (links, readouts, approvals) and the **GTM Content Manager App** (instrument authoring, page content).

### Key User Journeys

- **BD / Sales Reps:** View offering stories. Use **G**o-To-Market **U**tility **S**idekick (**GUS**) to build personalized prospect engagement landing pages (Experience Cloud). Track opportunity assessments, review prospect feedback, and chat with GUS to generate custom Offering Assessment Readouts.
- **Prospects:** Access password-protected, offering-customized Experience Cloud sites. Submit scored assessments and review finalized strategy readouts sent by reps.
- **Content Editors:** Configure the global framework, stories, and templated configurator pages. Review content feedback from reps. Build AI-scored logic and branching paths for Assessments (Instruments).

### Environment Configuration

- **Org Status:** `gtm-dev` (Org ID: `00DgK00000XZieHUAT`) is treated as **Production**. There is no staging environment. Every destructive change or seed script lands directly on live prospect data.
- _Note: This operational risk will persist until migration to the core Publicis Sapient Salesforce Org is finalized._

---

## 2. Repository Layout & Artifacts

### Core Directories

- `force-app/main/default/`: The standard SFDX source tree containing metadata (objects, classes, LWCs, experiences, flows, triggers, profiles).
- `migration-accelerator/instrument/<offering-key>/`: The single source of truth for assessment instruments (YAML files defining questions, scoring, gates, and branching).
- `scripts/`: Local utility files including `deploy.sh`, `deploy-fresh-org.sh`, `build-instrument.py`, and `check-references.py`.
- `data/seed/`: Initial database records stored in standard `sf data tree` JSON format.
- `docs/`: System documentation sub-divided into `architecture/` (ADRs), `specs/` (features), `runbooks/` (ops workflows), and `backlog.md` (living work sessions decision log).
- `docs/agent-artifacts/`: Ephemeral output from coding agents. (Must be explicitly promoted to `architecture/` or `specs/` by a human to be deemed authoritative).

### Layout Constraints

- **YAML Is Truth:** Always author instrument changes in the `migration-accelerator/` YAML directories.
- **Do Not Hand-Edit Metadata:** Never manually edit the generated `force-app/main/default/customMetadata/GTM_Assessment_*` XML files. They are auto-compiled, validated, and stamped via `scripts/build-instrument.py`.
- _Exception:_ The 14 core hand-authored `GTM_Assessment_Question.*` metadata records are read-only for the build script and can be safely modified.
- **Static Prototype:** The root `index.html` and `migration-accelerator/*.html` files are legacy pre-Salesforce static prototypes. They are inert and not deployed.

---

## 3. Technology Stack

- **Platform:** Salesforce DX source format, `sf` CLI, API Version 62.0 (`sfdx-project.json`).
- **Backend/Frontend:** Apex + LWC.
- **Testing framework:** Jest execution via `@salesforce/sfdx-lwc-jest` (`npm test`).
- **Experience Cloud:** Built on Aura using the `ChatterNetworkPicasso` template (Not LWR). No custom namespace is utilized.

---

## 4. Engineering Working Rules

- **Contract First:** Before implementing any feature, you must write the schema, mock layout, Apex signatures, LWC data contracts, and validation rules into `docs/architecture/`. These files are the source of truth; undocumented dependencies or contract drift are blocked defects.
- **Parallel Creation:** LWC and Apex development can proceed in parallel threads, provided both strictly build against the pre-defined architectural contracts.
- **Continuous Debug Loops:** On any build, test, or deployment failure, you must capture the trace, isolate the exact file, fix the structural root cause, and re-run immediately. Do not build new features on top of an unresolved failure.
- **Plan Before Action:** Any non-trivial schema changes, new objects, or new components require a strict design plan. Prefer minimal, reversible modifications.

---

## 5. Deployment Conventions (`gtm-dev`)

### Script Commands

- **Standard Deploy:** `./scripts/deploy.sh <org-alias> [--run-tests]`
  - Executes a two-pass deployment (core metadata first, then custom metadata records with up to 4 retries to handle flaky `GTM_Offering__mdt` records).
- **Zero-Org Deploy:** `./scripts/deploy-fresh-org.sh <org-alias> [--run-tests] [--check-only] [--with-profiles] [--with-agent]`
  - An unverified, 8-pass script intended _only_ for completely empty orgs. Review caveats in `docs/runbooks/fresh-org-deploy.md` before attempting.

### CLI & Post-Deploy Gaps

- **The `-c` Flag Warning:** In the `sf` CLI, the `-c` flag means `--ignore-conflicts`. It is **NOT** a dry run. To perform a safe validation test without altering the org, you must explicitly type out `--dry-run`.
- **Experience Cloud Sync:** Deployments touching `force-app/main/default/experiences/` only alter the draft state. You must run `sf community publish -n "<site name>"` (or publish via Experience Builder) for guest users to see modifications.

---

## 6. Systemic Codebase Gotchas

### 🔐 FLS & Permission Set Deficiencies

Any newly introduced field, object, or tab will be completely invisible to profiles respecting Field-Level Security until explicitly added to a permission set. Granting permissions is a mandatory part of a component's **Definition of Done**.

Ensure new schema additions are mapped across the 5 core project permission sets located in `force-app/main/default/permissionsets/`:

- `GTM_Config_Manager`
- `GTM_Config_View_All`
- `GTM_Assessment_Guest`
- `GTM_Story_Guest`
- `GTM_Platform_Visibility`

### 👥 Duplicate-Detection Interceptions

- **Naive Inserts:** Standard `insert` DML operations on records containing duplicate indicators (such as Lead emails, Prospect contact entries, or unique offering tokens) will be intercepted and thrown as fatal errors by active Salesforce Duplicate Rules. Always implement duplicate-checking logic, use `Database.insert(records, false)`, or bypass using matching criteria validation loops before committing data records.
