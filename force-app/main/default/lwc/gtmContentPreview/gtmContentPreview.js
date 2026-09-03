import { LightningElement, api, track } from 'lwc';

export default class GtmContentPreview extends LightningElement {
    @api offeringKey = 'migration-accelerator';
    @api templateType = 'story';
    @api records = [];

    @track contentMap = {};

    connectedCallback() {
        this.buildContentMap();
    }

    willUpdateComponent(changes) {
        if (changes.records) {
            this.buildContentMap();
        }
    }

    buildContentMap() {
        const map = {};
        const sections = this.records || [];
        sections.forEach((section) => {
            section.records.forEach((record) => {
                const key = `${section.sectionKey}::${record.fieldKey}`;
                map[key] = record;
            });
        });
        this.contentMap = map;
    }

    getValue(sectionKey, fieldKey) {
        const key = `${sectionKey}::${fieldKey}`;
        const record = this.contentMap[key];
        if (!record) return null;
        if (record.textValue) return record.textValue;
        if (record.richValue) return record.richValue;
        if (record.jsonValue) return record.jsonValue;
        return null;
    }

    getJsonValue(sectionKey, fieldKey) {
        const raw = this.getValue(sectionKey, fieldKey);
        if (!raw) return [];
        try {
            return JSON.parse(raw);
        } catch (e) {
            return [];
        }
    }

    // Hero section
    get heroEyebrow() { return this.getValue('hero', 'eyebrow'); }
    get heroHeadline() { return this.getValue('hero', 'headline'); }
    get heroSubheadline() { return this.getValue('hero', 'subhead'); }

    // Problem section
    get problemLede() { return this.getValue('problem', 'lede'); }
    get problemChips() { return this.getJsonValue('problem', 'chips'); }
    get problemClose() { return this.getValue('problem', 'close'); }

    // BD section
    get bdHead() { return this.getValue('bd', 'head'); }
    get bdLede() { return this.getValue('bd', 'lede'); }
    get bdPitchOldChips() { return this.getJsonValue('bd', 'pitchOldChips'); }
    get bdPitchNewChips() { return this.getJsonValue('bd', 'pitchNewChips'); }
    get bdUseCases() { return this.getJsonValue('bd', 'useCases'); }

    // Mechanism section
    get mechanismHead() { return this.getValue('mechanism', 'head'); }
    get mechanismSub() { return this.getValue('mechanism', 'sub'); }
    get mechanismSteps() { return this.getJsonValue('mechanism', 'routeSteps'); }
    get mechanismProofCtaText() { return this.getValue('mechanism', 'proofCtaText'); }
    get mechanismProofDemoRoot() { return this.getValue('mechanism', 'proofDemoRoot'); }
    get mechanismProofDemoDeps() { return this.getJsonValue('mechanism', 'proofDemoDeps'); }

    // Capabilities section
    get capabilitiesCards() { return this.getJsonValue('capabilities', 'cards'); }
    get capabilitiesBonusCard() { return this.getValue('capabilities', 'bonusCard'); }

    // Client profile section
    get clientProfileStatBig() { return this.getValue('clientProfile', 'statBig'); }
    get clientProfileStatDesc() { return this.getValue('clientProfile', 'statDesc'); }
    get clientProfileNote() { return this.getValue('clientProfile', 'note'); }

    // Closing section
    get closingHead() { return this.getValue('closing', 'head'); }
    get closingSub() { return this.getValue('closing', 'sub'); }
}
