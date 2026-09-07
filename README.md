# GTM Offerings

A Salesforce Lightning/Apex/LWC application for Publicis Sapient's BD/sales
reps: it builds engagement links that carry a prospect through a
configurable offering story, an AI-scored assessment questionnaire, and a
rep-authored, natively-approved readout, all without the prospect logging
in. Reps and content authors work in two Lightning apps — **GTM Offerings**
and **GTM Content Manager** — and prospects land on a single guest-facing
Experience Cloud site.

Everything under `force-app/` is standard Salesforce DX source, deployed
straight from this repo with the `sf` CLI — there's no separate build step
or export.

## Start here

- **[`CLAUDE.md`](./CLAUDE.md)** — the agent-facing reference: repo layout,
  deploy conventions, systemic gotchas, and where everything else lives.
  Read this first if you're working in the codebase, human or agent.
- **[`DEPLOYMENT.md`](./DEPLOYMENT.md)** — how to deploy this to a Salesforce
  org, and what a deploy can't do for you.
- **[`docs/architecture/overview.md`](./docs/architecture/overview.md)** —
  the system's container diagram and the readout's status lifecycle.

## Legacy prototype

`index.html` and `migration-accelerator/*.html` at the repo root are a
pre-Salesforce static-HTML prototype of the offering story/configurator
flow. They aren't deployed anywhere in the current app; the SFDX app under
`force-app/` is what actually runs. They're left in place for now — whether
to remove them is an open call, not decided here.

## Maintainers

See [`MAINTAINERS.md`](./MAINTAINERS.md).
