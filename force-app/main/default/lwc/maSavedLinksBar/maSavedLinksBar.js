import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyConfigurations from '@salesforce/apex/MaSavedConfigurationController.getMyConfigurations';
import deleteConfiguration from '@salesforce/apex/MaSavedConfigurationController.deleteConfiguration';

export default class MaSavedLinksBar extends LightningElement {
    hasAccess = false;
    isOpen = false;
    groups = [];

    _wiredResult;

    @wire(getMyConfigurations)
    wiredConfigurations(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.hasAccess = true;
            this.groups = this.groupRecords(data);
        } else if (error) {
            // Guest users (and anyone else without the MA Config Manager
            // permission set) hit this path — no class/object access. The
            // bar simply doesn't render for them; this is not a real error
            // to surface.
            this.hasAccess = false;
            this.groups = [];
        }
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get toggleLabel() {
        return this.isOpen ? 'My Saved Links ▲' : 'My Saved Links ▾';
    }

    get panelClass() {
        return this.isOpen ? 'sl-panel open' : 'sl-panel';
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
    }

    async handleDelete(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        try {
            await deleteConfiguration({ recordId });
            await refreshApex(this._wiredResult);
        } catch (e) {
            // Deletion failing (e.g. someone else's record, no delete
            // access) just leaves the row in place — nothing to recover.
        }
    }

    groupRecords(records) {
        const byOffering = new Map();

        records.forEach((rec) => {
            const offeringKey = rec.Offering__c || 'Other';
            if (!byOffering.has(offeringKey)) {
                byOffering.set(offeringKey, new Map());
            }
            const byIndustry = byOffering.get(offeringKey);
            const industryKey = rec.Industry__c || 'Generic';
            if (!byIndustry.has(industryKey)) {
                byIndustry.set(industryKey, []);
            }
            byIndustry.get(industryKey).push({
                id: rec.Id,
                label: rec.Company__c || rec.Name,
                url: rec.Generated_URL__c,
                owner: rec.Owner ? rec.Owner.Name : '',
                date: rec.CreatedDate
                    ? new Date(rec.CreatedDate).toLocaleDateString()
                    : ''
            });
        });

        const groups = [];
        byOffering.forEach((byIndustry, offeringName) => {
            const industries = [];
            byIndustry.forEach((links, industryName) => {
                industries.push({ key: `${offeringName}-${industryName}`, name: industryName, links });
            });
            groups.push({ key: offeringName, name: offeringName, industries });
        });
        return groups;
    }
}
