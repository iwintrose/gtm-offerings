# ADR-0003 — Single trigger point per side effect

**Status:** Accepted

## Context

Salesforce lets more than one piece of automation react to the same DML —
an Apex trigger/class and a Flow can both fire on the same record save, each
unaware of the other. On this project that produced a real bug: a
notification/email side effect fired twice because both an Apex class and a
Flow were independently reacting to the same underlying DML for what was
meant to be one outcome. The fix was straightforward once found, but finding
it meant tracing two independent automation paths that had no reason to know
about each other.

## Decision

Never let two independent automations — an Apex trigger/class and a Flow, or
two Flows — both react to the same DML for the same side effect. Pick one
owner per side effect (email send, record creation, status update) and keep
it there. `GtmReadoutApprovalSync.trigger` and the approval process's
workflow field updates are the current example of automation that is allowed
to coexist because each owns a distinct piece of the state transition, not
the same one.

## Consequences

- Some automation that "could" be a quick Flow instead has to be added to
  existing Apex, or vice versa, specifically to keep one owner per side
  effect rather than picking whichever tool is momentarily more convenient.
- Anyone adding a new side effect (email, task creation, a field update
  driven by a status change) has to check what already owns that DML before
  adding a second path to it.
