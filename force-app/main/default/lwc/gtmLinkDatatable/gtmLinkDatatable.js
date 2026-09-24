/**
 * lightning-datatable subclass adding one custom cell type, `gtmLink`, used
 * by both the Pages table (gtmRepLinkTableModel.js: Account, Contact) and
 * the Assessments table (gtmAssessmentsTableModel.js: Contact, Account) so
 * neither has to hand-roll its own cell rendering (see docs/architecture/
 * gtm-link-stage-filter.md and gtm-assessments-table.md, "Account/Contact
 * cell type").
 *
 * This is the documented `lightning-datatable` extension pattern (a
 * `static customTypes` map on a subclass); `<lightning-datatable>` itself
 * has no supported way to accept a custom cell type without subclassing.
 * All other lightning-datatable behavior (sort, infinite loading, row
 * actions, etc.) is inherited unchanged.
 */
import LightningDatatable from 'lightning/datatable';
import gtmLinkCellTemplate from './gtmLinkCellTemplate.html';

export default class GtmLinkDatatable extends LightningDatatable {
    static customTypes = {
        gtmLink: {
            template: gtmLinkCellTemplate,
            standardCellLayout: true,
            typeAttributes: ['label', 'name', 'disabled', 'title', 'targetId', 'idField']
        }
    };
}
