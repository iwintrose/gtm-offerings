import { LightningElement, track } from 'lwc';
import isConfigManager from '@salesforce/apex/MaSavedConfigurationController.isConfigManager';

export default class MaAdminBar extends LightningElement {
    @track _isAdmin = false;
    @track _editMode = false;

    get bannerClass() { return 'ab' + (this._editMode ? ' ab--on' : ''); }
    get fabClass() { return 'fab' + (this._editMode ? ' fab--on' : ''); }
    get fabLabel() { return this._editMode ? 'Edit Mode' : 'Admin'; }

    connectedCallback() {
        isConfigManager()
            .then(() => { this._isAdmin = true; })
            .catch(() => { /* guest or no permission — render nothing */ });
    }

    handleToggle() {
        this._editMode = !this._editMode;
        window.dispatchEvent(new CustomEvent('maadminedit', { detail: { active: this._editMode } }));
    }

    handleExit() {
        this._editMode = false;
        window.dispatchEvent(new CustomEvent('maadminedit', { detail: { active: false } }));
    }
}
