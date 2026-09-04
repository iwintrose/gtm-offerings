import { LightningElement, track } from 'lwc';

/**
 * Diagnostic only. Embeds c-ma-story and nothing else, to establish whether a
 * component with Experience Cloud targets can be composed inside a Lightning
 * tab at all. Two attempts to restore the editor's preview both blanked the
 * tab, and the cause has not been identified; this isolates the one variable.
 *
 * Delete once the question is settled.
 */
export default class GtmEmbedProbe extends LightningElement {
    @track showStory = false;

    // Static markers. If these render and the story does not, the probe itself
    // is fine and the embed is the problem. If nothing renders at all, the
    // mere presence of c-ma-story in the template breaks the module.
    get marker() { return 'Probe mounted. If you can read this, the component itself renders.'; }

    handleShow() { this.showStory = true; }
}
