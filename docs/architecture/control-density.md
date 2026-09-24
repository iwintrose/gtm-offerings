# Control density (compact buttons and controls)

Convention: every interactive control in GTM LWC bundles is 32px tall, the same
as `--gtm-control-h` in `gtmFilterBar`. Use it as `var(--gtm-control-h, 32px)`.

Salesforce-first: `lightning-button`, `lightning-button-icon` (default size),
`lightning-button-menu` and `slds-button` are already 32px, so they are left
alone (`lightning-button` has no `size` attribute). Custom CSS is only used
where a bespoke button had its own vertical padding instead of a height:

| Bundle | Selector | Change |
|---|---|---|
| gtmInstrumentAuthor | `.ia-btn` | padding-based height -> 32px |
| conduitDataExtract | `.action-btn` | padding-based height -> 32px |
| gtmContentManager | `.gcm-settings-btn` | padding-based height -> 32px |
| gtmContentHome | `.off-foot-btn` | min-height 32px (row hit target) |

Owned elsewhere and not touched: gtmFilterBar, gtmRepLinkFinder,
gtmReadoutsOverview, gtmAssessmentsTableModel.
