import { LightningElement } from 'lwc';

/**
 * Jest stub for the `lightning/modal` base component.
 *
 * sfdx-lwc-jest ships stubs for `lightning/modalHeader`,
 * `lightning/modalBody`, and `lightning/modalFooter` (the sub-components a
 * modal's own template uses), but none for `lightning/modal` itself -- the
 * base class a modal component EXTENDS. Without this, any component
 * (`import LightningModal from 'lightning/modal'`) fails to resolve under
 * Jest at all.
 *
 * Real behavior (per the platform's documented `lightning/modal` contract):
 * `MyModal.open(props)` mounts the modal and returns a Promise that resolves
 * with whatever value the modal instance passes to `this.close(value)`.
 * `this.dismiss(reason)` is the same idea for a "closed without a result"
 * path. Tests that need to assert *how* a caller invoked `.open()` should
 * `jest.mock('c/myModal')` and assert on the mock's calls directly, the same
 * way any other child component is asserted on in this codebase -- this
 * stub only exists so modules that import `lightning/modal` load at all.
 */
export default class LightningModal extends LightningElement {
    static open() {
        return Promise.resolve(undefined);
    }

    close(value) {
        return value;
    }

    dismiss(reason) {
        return reason;
    }
}
