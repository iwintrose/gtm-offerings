#!/usr/bin/env python3
"""
One-time migration: seeds the 7 industry story blocks, 6 FAQ items, and 1
story-defaults record -- currently hardcoded as JS constants in
force-app/main/default/lwc/maConfigData/maConfigData.js and
force-app/main/default/lwc/maStory/maStory.js -- into the GTM Offerings CMS
Workspace, as real ma_industry_story / ma_faq_item / ma_story_setting
content records.

NOT idempotent, unlike deploy.sh and setup-cms-workspace.sh -- re-running
this creates duplicate records. It's a one-time cutover script, kept here
for the record of exactly what was seeded and how, not something meant to
run repeatedly. Once MaStoryContentController.cls reads from CMS instead of
the hardcoded constants, this script (and the constants it mirrors) become
historical.

All records are created as Drafts. Publishing needs CMS Workspace
Publisher/Admin access granted to the authoring user first (Setup >
Digital Experiences > CMS Workspaces > GTM Offerings > Access) -- a
System Administrator profile does not imply this automatically, and the
publish API itself (POST .../versions) returned FUNCTIONALITY_NOT_ENABLED
against this org's default access for the seeding run that produced this
script. See DEPLOYMENT.md.

Usage:
    python3 scripts/seed-cms-content.py <org-alias-or-username>
"""
import json
import subprocess
import sys

import requests

OFFERING_KEY = "migration-accelerator"

INDUSTRIES = {
    "fintech": {
        "label": "Financial Services",
        "coverSub": "For banks and insurers, a migration is a compliance event as much as a technology one. Here’s how we move you without putting consent, disclosures, or audit trails at risk.",
        "problem": "Your marketing runs under the regulator’s eye. Consent states, suppression lists, disclosure language, and audit trails aren’t metadata, they’re obligations, and in most enterprises they’re spread across a decade of undocumented campaigns.",
        "useCase": "Take a global retail bank moving off Eloqua: thousands of assets across regions, each carrying consent rules and regional disclosures nobody fully documented.",
        "solution": "The Accelerator reads the whole environment and preserves what regulators care about, consent, suppression, disclosures, and audit lineage, so nothing compliance-critical is ever rebuilt from memory.",
        "unique": ["Consent & suppression preserved", "Disclosure & audit lineage intact", "Data residency across regions"],
        "proofLine": "Every object mapped with its consent and suppression state, so the plan is defensible, not just fast.",
        "whyLine": "Deep delivery experience with regulated financial institutions, where a comms error carries real regulatory weight.",
        "whyHead": "Built for regulated financial marketing.",
        "demoRoot": "Rate-change notification",
        "demoDeps": ["Statement email", "Disclosure block", "Rates data extension", "Compliance footer"],
    },
    "medtech": {
        "label": "MedTech",
        "coverSub": "For medical-device organizations, promotional content is regulated content. Here’s how we migrate without losing MLR-approved assets or blurring the HCP/patient line.",
        "problem": "Every promotional asset has passed MLR review, and HCP and patient audiences must never bleed into each other. A migration that treats them as ordinary emails puts approvals, and compliance, at risk.",
        "useCase": "Take a global device manufacturer moving to Salesforce: campaigns spanning HCP and patient journeys, each asset tied to an approval record.",
        "solution": "The Accelerator carries approved content, claims, and the approval records behind them into the new platform, with HCP and patient audiences kept distinct by construction.",
        "unique": ["MLR-approved content preserved", "HCP vs. patient separation", "Adverse-event & consent handling"],
        "proofLine": "Each asset mapped with its approval lineage, so nothing regulated gets rebuilt off-record.",
        "whyLine": "Hands-on delivery for regulated medical-device marketing, where approval and audience integrity are non-negotiable.",
        "whyHead": "Built for regulated medical-device marketing.",
        "demoRoot": "HCP product update",
        "demoDeps": ["Approved email", "ISI safety block", "HCP data extension", "Brand header"],
    },
    "lifesci": {
        "label": "Life Sciences",
        "coverSub": "For pharma and life sciences, content is regulated and every market differs. Here’s how we migrate without losing approval lineage or market-specific rules.",
        "problem": "Regulated content, many markets, and Veeva-shaped approval workflows. The risk in a migration isn’t rebuilding an email, it’s losing the approval lineage and the market-by-market rules that make it compliant.",
        "useCase": "Take a global pharma brand consolidating onto Salesforce: the same campaign expressed differently per market, each version approved separately.",
        "solution": "The Accelerator preserves approval lineage and market-specific rules as it moves your content, so compliance travels with the campaign, market by market.",
        "unique": ["Approval lineage kept auditable", "Market-by-market content rules", "Regulated content-system integration"],
        "proofLine": "Every market variant mapped with its approval record, so nothing regulated ships unreviewed.",
        "whyLine": "Global life-sciences delivery experience, across regulated markets and content systems.",
        "whyHead": "Built for regulated, multi-market life sciences.",
        "demoRoot": "Patient support program",
        "demoDeps": ["Approved email — US", "Approved email — EU", "Consent data extension", "Localized footer"],
    },
    "media": {
        "label": "Media & Entertainment",
        "coverSub": "For media and entertainment, the challenge is scale and breadth. Here’s how we migrate dozens of brands and millions of subscribers without a visible seam.",
        "problem": "Dozens of brands, millions of subscribers, campaigns shipping daily. Shared assets are reused across franchises, and at your scale a single dropped journey is a visible failure to real audiences.",
        "useCase": "Take a streaming-and-studios group moving onto Salesforce: overlapping brands sharing templates and data, subscriber lifecycles running around the clock.",
        "solution": "The Accelerator maps the whole estate across brands, finds what’s shared, and sequences the rebuild so subscribers never feel the move, and shared assets are built once, not per brand.",
        "unique": ["Many brands & business units", "Subscriber lifecycle at scale", "Shared assets built once across franchises"],
        "proofLine": "Shared assets found and de-duplicated across brands, built once, never twice.",
        "whyLine": "Experience delivering personalization and lifecycle at consumer-media scale.",
        "whyHead": "Built for personalization at media scale.",
        "demoRoot": "New season launch",
        "demoDeps": ["Announcement email", "Trailer content block", "Subscriber segment", "Brand header"],
    },
    "transport": {
        "label": "Transportation & Logistics",
        "coverSub": "For transportation and logistics, comms are operational. Here’s how we migrate real-time, triggered journeys without a customer feeling it at the worst possible moment.",
        "problem": "Half your comms are operational, itineraries, disruptions, delay alerts, loyalty. They’re real-time and triggered; a migration that drops one leaves a customer stranded without an update.",
        "useCase": "Take an international airline moving onto Salesforce: hundreds of triggered journeys firing on operational events, each with dependencies nobody has fully traced.",
        "solution": "The Accelerator maps every trigger and its dependencies, so operational journeys are rebuilt intact and in the right order, not rediscovered after go-live.",
        "unique": ["Operational & triggered comms", "Real-time journeys preserved", "Global, multi-region delivery"],
        "proofLine": "Every triggered journey mapped with its dependencies, so nothing operational goes dark at cutover.",
        "whyLine": "Delivery experience where operational comms are mission-critical, not marketing nice-to-haves.",
        "whyHead": "Built for mission-critical operational comms.",
        "demoRoot": "Flight disruption alert",
        "demoDeps": ["Delay email", "Rebooking block", "Itinerary data extension", "Loyalty footer"],
    },
    "government": {
        "label": "Government & Public Sector",
        "coverSub": "For government and public sector, citizen comms must be accessible, secure, and plain. Here’s how we migrate while carrying the compliance, not just the templates.",
        "problem": "Citizen communications must be accessible (WCAG / Section 508), secure, multilingual, and plain-spoken. A migration has to carry accessibility and security posture, not just move the content.",
        "useCase": "Take a federal agency consolidating onto Salesforce: citizen notifications across programs and languages, each bound by accessibility and security requirements.",
        "solution": "The Accelerator preserves accessibility, security posture, and multilingual content as it migrates, so citizen comms stay compliant by construction.",
        "unique": ["Accessibility (WCAG / Section 508)", "Security & data-handling posture", "Multilingual, plain-language content"],
        "proofLine": "Content mapped with its accessibility and language requirements, so compliance isn’t rebuilt by hand.",
        "whyLine": "Public-sector delivery experience where accessibility and security are requirements, not options.",
        "whyHead": "Built for accessible, secure citizen comms.",
        "demoRoot": "Benefits renewal notice",
        "demoDeps": ["Notice email", "Accessibility footer", "Citizen data extension", "Translation set"],
    },
    "municipal": {
        "label": "Municipal & Civic",
        "coverSub": "For cities and civic agencies, it’s citizen services on lean teams. Here’s how we consolidate without dropping the alerts and services residents rely on.",
        "problem": "Alerts, services, and notifications span departments, often on lean teams and tight budgets. The migration has to consolidate without dropping the citizen-facing services residents depend on.",
        "useCase": "Take a metro authority consolidating several departments onto one platform: overlapping alert systems and service notifications, built up independently over years.",
        "solution": "The Accelerator maps every department’s comms, finds the overlap, and plans one consolidated estate, so nothing citizen-facing falls through the cracks.",
        "unique": ["Multi-department consolidation", "Citizen alerts & service comms", "Accessible, budget-aware delivery"],
        "proofLine": "Every department’s comms mapped and de-duplicated, so consolidation doesn’t drop a service.",
        "whyLine": "Civic delivery experience, consolidating services for lean public-sector teams.",
        "whyHead": "Built for lean, multi-department civic teams.",
        "demoRoot": "Service outage alert",
        "demoDeps": ["Alert email", "SMS block", "Resident data extension", "Department footer"],
    },
}

FAQS = [
    {
        "question": "Does it let us run a migration with fewer people?",
        "verdict": "Yes",
        "answer": "The platform drafts the first pass, inventory, descriptions, build requirements, and a person reviews and refines instead of starting from nothing.",
    },
    {
        "question": "Does it let us do it faster?",
        "verdict": "Yes",
        "answer": "Assessment runs in about an hour instead of weeks. A full plan for a mid-size environment fits inside a single sprint.",
    },
    {
        "question": "Can it actually execute the migration, or just plan it?",
        "verdict": "Yes",
        "answer": "For supported objects, the platform previews the change with a dry run, executes it live, and keeps rollback ready if anything doesn't land clean.",
    },
    {
        "question": "Does it mean fewer defects?",
        "verdict": "Yes",
        "answer": "Dependency-aware planning won't let a destination ship without something it needs to run, the exact class of miss that spreadsheet planning lets through routinely.",
    },
    {
        "question": "Does it give us better scoping, less risk?",
        "verdict": "Yes",
        "answer": "The health score comes from an automated audit of the real environment, not client-reported counts, which is usually where scoping risk starts.",
    },
    {
        "question": "Does it let us scale without deep platform specialists on every deal?",
        "verdict": "Qualified yes",
        "answer": "Platform knowledge, field semantics, translation heuristics, vocabulary, lives in the platform, so someone without years of Eloqua or SFMC experience can operate it credibly. A specialist should still review and approve.",
    },
]

STORY_SETTING = {
    "defaultSourcePlatform": "Eloqua",
    "defaultTargetPlatform": "Salesforce Marketing Cloud",
    "defaultAssetCount": "4,128",
    "defaultDependencyCount": "9,640",
    "defaultHealthScore": "62",
    "genericDemoRoot": "Welcome Series",
    "genericDemoDeps": ["Welcome email 1", "Welcome email 2", "Shared data extension", "Brand header"],
    "genericChips": ["Undocumented environment", "Scope you can’t confidently size", "Risk of breaking what works"],
    "swatches": [
        "PS Coral (default)|EE3D23",
        "Corporate blue|0B5FFF",
        "Slate navy|1E293B",
        "Forest green|166534",
        "Deep purple|5B21B6",
        "Steel gray|44403C",
    ],
}


def get_org_context(target_org):
    info = json.loads(subprocess.check_output(["sf", "org", "display", "--target-org", target_org, "--json"]))
    token_info = json.loads(subprocess.check_output(["sf", "org", "auth", "show-access-token", "--target-org", target_org, "--json"]))
    return {
        "base_url": f"{info['result']['instanceUrl']}/services/data/v{info['result']['apiVersion']}",
        "token": token_info["result"]["accessToken"],
    }


def find_workspace_id(ctx, api_name="GTM_Offerings"):
    resp = requests.get(f"{ctx['base_url']}/connect/cms/spaces", headers={"Authorization": f"Bearer {ctx['token']}"})
    resp.raise_for_status()
    for space in resp.json().get("spaces", []):
        if space.get("apiName") == api_name:
            return space["id"]
    raise SystemExit(f"No CMS Workspace found with apiName={api_name}. Run scripts/setup-cms-workspace.sh first.")


def create_content(ctx, space_id, content_type, title, content_body):
    body = {
        "contentSpaceOrFolderId": space_id,
        "contentType": content_type,
        "title": title,
        "contentBody": content_body,
    }
    resp = requests.post(
        f"{ctx['base_url']}/connect/cms/contents",
        headers={"Authorization": f"Bearer {ctx['token']}", "Content-Type": "application/json"},
        data=json.dumps(body),
    )
    if resp.status_code != 201:
        print(f"  FAILED ({resp.status_code}): {title}")
        print(f"    {resp.text}")
        return None
    result = resp.json()
    print(f"  OK: {title}  ->  {result['contentKey']}")
    return result["contentKey"]


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/seed-cms-content.py <org-alias-or-username>")
        sys.exit(1)
    target_org = sys.argv[1]

    ctx = get_org_context(target_org)
    space_id = find_workspace_id(ctx)
    print(f"Seeding into Workspace {space_id}\n")

    print(f"== {len(INDUSTRIES)} industry story records ==")
    for key, data in INDUSTRIES.items():
        create_content(
            ctx,
            space_id,
            "ma_industry_story",
            f"{data['label']} — Migration Accelerator",
            {
                "title": f"{data['label']} — Migration Accelerator",
                "offeringKey": OFFERING_KEY,
                "industryKey": key,
                "industryLabel": data["label"],
                "coverSub": f"<p>{data['coverSub']}</p>",
                "problem": f"<p>{data['problem']}</p>",
                "useCase": f"<p>{data['useCase']}</p>",
                "solution": f"<p>{data['solution']}</p>",
                "uniquePoints": "\n".join(data["unique"]),
                "proofLine": data["proofLine"],
                "whyLine": data["whyLine"],
                "whyHead": data["whyHead"],
                "demoRoot": data["demoRoot"],
                "demoDeps": "\n".join(data["demoDeps"]),
            },
        )

    print(f"\n== {len(FAQS)} FAQ records ==")
    for i, faq in enumerate(FAQS, start=1):
        create_content(
            ctx,
            space_id,
            "ma_faq_item",
            faq["question"],
            {
                "title": faq["question"],
                "offeringKey": OFFERING_KEY,
                "answer": f"<p>{faq['answer']}</p>",
                "verdict": faq["verdict"],
                "displayOrder": str(i),
            },
        )

    print("\n== 1 story-defaults record ==")
    create_content(
        ctx,
        space_id,
        "ma_story_setting",
        "Migration Accelerator — Story Defaults",
        {
            "title": "Migration Accelerator — Story Defaults",
            "offeringKey": OFFERING_KEY,
            "defaultSourcePlatform": STORY_SETTING["defaultSourcePlatform"],
            "defaultTargetPlatform": STORY_SETTING["defaultTargetPlatform"],
            "defaultAssetCount": STORY_SETTING["defaultAssetCount"],
            "defaultDependencyCount": STORY_SETTING["defaultDependencyCount"],
            "defaultHealthScore": STORY_SETTING["defaultHealthScore"],
            "genericDemoRoot": STORY_SETTING["genericDemoRoot"],
            "genericDemoDeps": "\n".join(STORY_SETTING["genericDemoDeps"]),
            "genericChips": "\n".join(STORY_SETTING["genericChips"]),
            "swatches": "\n".join(STORY_SETTING["swatches"]),
        },
    )

    print("\nDone. All records created as Drafts -- see this script's docstring")
    print("for why publishing needs a separate manual/Setup step.")


if __name__ == "__main__":
    main()
