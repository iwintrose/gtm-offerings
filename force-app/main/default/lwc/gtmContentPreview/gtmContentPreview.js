import { LightningElement, api, track } from 'lwc';

export default class GtmContentPreview extends LightningElement {
    @api offeringKey = 'ma-migrator';
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
    get heroSubheadline() { return this.getValue('hero', 'subheadline'); }
    get heroBgImage() { return this.getValue('hero', 'bgImage'); }

    // Problem section
    get problemHeadline() { return this.getValue('problem', 'headline'); }
    get problemPitchOldChips() { return this.getJsonValue('problem', 'pitchOldChips'); }
    get problemBody() { return this.getValue('problem', 'body'); }

    // BD section
    get bdHeadline() { return this.getValue('bd', 'headline'); }
    get bdPitchNewChips() { return this.getJsonValue('bd', 'pitchNewChips'); }
    get bdBody() { return this.getValue('bd', 'body'); }

    // Mechanism section
    get mechanismHeadline() { return this.getValue('mechanism', 'headline'); }
    get mechanismSteps() { return this.getJsonValue('mechanism', 'steps'); }
    get mechanismBody() { return this.getValue('mechanism', 'body'); }

    // Capabilities section
    get capabilitiesHeadline() { return this.getValue('capabilities', 'headline'); }
    get capabilitiesCards() { return this.getJsonValue('capabilities', 'cards'); }

    // Client profile section
    get clientprofileHeadline() { return this.getValue('clientprofile', 'headline'); }
    get clientprofileBody() { return this.getValue('clientprofile', 'body'); }

    // Closing section
    get closingHeadline() { return this.getValue('closing', 'headline'); }
    get closingBody() { return this.getValue('closing', 'body'); }
}
