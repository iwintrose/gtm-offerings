# feat(filters): compact filter bar, Pages and Assessments filters (issue-filters-integrated)

## Summary
- **R1 compact filter bar**: `gtmFilterBar` popover bar with a More popover, replacing the inline filter rows.
- **R2 Pages**: Account/Contact folded into filters, row actions, Back to links.
- **R3 Assessments**: server-backed Account and Contact filters replace the browse-mode toggle.
- **Layout fix**: filter toolbar pinned to the top so result changes never shift it.
- **Plain-array / Aura-property fix**: list filters are sent to Apex as plain arrays (LWC proxies were dropped), and `AssessmentQuery` members use `@AuraEnabled` property syntax so Aura binds them.
- Temporary `[GTMRO]` diagnostics removed; no logging remains.

## Test plan
- `npm test` passes; `python3 scripts/check-references.py` reports 0 deploy-blocking.
- In the Assessments and Pages tabs, apply each filter (single and multi-value) and confirm rows change, counts update, and clearing restores the full list.
- Account and Contact filters return only matching assessments.
- Rapidly change filters or sort: the latest result wins, no stale rows.
- Toolbar stays fixed when results shrink or grow; More popover opens and applies.
- Row actions and Back to links work on Pages; a rep sees only their own records.
