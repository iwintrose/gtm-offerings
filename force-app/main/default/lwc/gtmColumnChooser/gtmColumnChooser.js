import { LightningElement, api } from 'lwc';
import { normalizeKeys, defaultKeys, isDefault } from 'c/gtmColumnState';

const EDGE = 8; // px kept clear at the viewport edge
const GUARD_HINT = 'At least one column must stay shown';
const OPEN_EVENT = 'gtmpopoveropen'; // document-level: one popover at a time

/**
 * Presentational, CONTROLLED column chooser. Owns only open/close state; the
 * parent owns the visible keys. Contract: docs/architecture/gtm-column-chooser.md.
 */
export default class GtmColumnChooser extends LightningElement {
    @api label = 'Columns';

    _columns = [];
    _selectedKeys;
    @api
    get columns() {
        return this._columns;
    }
    set columns(v) {
        this._columns = Array.isArray(v) ? v : [];
    }
    @api
    get selectedKeys() {
        return this._selectedKeys;
    }
    set selectedKeys(v) {
        this._selectedKeys = Array.isArray(v) ? v : undefined;
    }

    isOpen = false;
    hint = '';
    liveText = '';
    _rev = 0;
    _focusPending = false;
    _refocusPending = false;
    _regroupPending = false;
    _placeOnce = false;
    _docClick = null;
    _attachTimer = null;
    _settleTimer = null;
    _settling = false;
    _pointerTimer = null;
    _pointerDown = false;
    _insideInteraction = false;
    _insideTimer = null;
    _outsideTimer = null;
    _onForeignOpen = null;
    _memo = {};

    connectedCallback() {
        this._onForeignOpen = (e) => {
            if (this.isOpen && (!e.detail || e.detail.source !== this)) this._close(false);
        };
        document.addEventListener(OPEN_EVENT, this._onForeignOpen);
    }

    disconnectedCallback() {
        this._detachDocClick();
        this._clearTimers();
        if (this._onForeignOpen) document.removeEventListener(OPEN_EVENT, this._onForeignOpen);
        this._onForeignOpen = null;
    }

    // ---- derived display -------------------------------------------------------

    get _pinnedEntries() {
        return this._columns.filter((c) => c.pinned);
    }
    get _keys() {
        return normalizeKeys(this._columns, this._selectedKeys);
    }
    get hasPinned() {
        return this._pinnedEntries.length > 0;
    }
    get pinnedLine() {
        return `Always shown: ${this._pinnedEntries.map((c) => c.label).join(', ')}`;
    }
    get triggerAria() {
        return `${this.label}, ${this._keys.length} of ${this._columns.length} shown`;
    }
    get expanded() {
        return this.isOpen ? 'true' : 'false';
    }
    get wrapClass() {
        return 'gtm-col-chooser' + (this.isOpen ? ' slds-is-open' : '');
    }
    get resetDisabled() {
        return isDefault(this._columns, this._selectedKeys);
    }
    // Content-stable identities (see _stable): pinned columns are never options.
    get options() {
        return this._stable(
            'o',
            this._columns.filter((c) => !c.pinned).map((c) => ({ label: c.label, value: c.key }))
        );
    }
    get value() {
        const on = new Set(this._keys);
        return this._stable(
            'v',
            this._columns.filter((c) => !c.pinned && on.has(c.key)).map((c) => c.key)
        );
    }
    // One-item list keyed by _rev: incrementing it re-creates the group (last-column guard).
    get groups() {
        return [{ rev: `g${this._rev}` }];
    }

    // The parent re-renders on every tick with NEW equal-content arrays. Handing the
    // base component a NEW options/value array makes it replace its inputs, which can
    // swallow the click's `change`. Keep identity while content is equal.
    _stable(name, val) {
        const sig = JSON.stringify(val);
        const hit = this._memo[name];
        if (hit && hit.sig === sig) return hit.val;
        this._memo[name] = { sig, val };
        return val;
    }

    // ---- change handling -------------------------------------------------------

    handleChange(event) {
        event.stopPropagation();
        const picked = new Set((event.detail && event.detail.value) || []);
        const keys = this._columns.filter((c) => c.pinned || picked.has(c.key)).map((c) => c.key);
        if (keys.length === 0) {
            // Last-column guard: ignore, explain, and re-create the group so the
            // base component's checkbox reverts (re-assigning value alone is UNVERIFIED).
            this.hint = GUARD_HINT;
            this._rev += 1;
            this._regroupPending = true;
            return;
        }
        this.hint = '';
        this._emit(keys);
    }

    handleReset() {
        this.hint = '';
        this._refocusPending = true;
        this._emit(defaultKeys(this._columns));
    }

    _emit(keys) {
        this.liveText = `${keys.length} of ${this._columns.length} columns shown`;
        this.dispatchEvent(new CustomEvent('columnschange', { detail: { keys } }));
    }

    // ==== POPOVER MECHANICS (mirrors gtmFilterBar B.13.2-B.13.5) ====================
    // Kept contiguous so a later shared extraction is mechanical.

    _clearTimers() {
        [this._pointerTimer, this._attachTimer, this._settleTimer, this._insideTimer, this._outsideTimer].forEach((t) => t && clearTimeout(t));
        this._insideTimer = null;
        this._outsideTimer = null;
        this._insideInteraction = false;
        this._pointerTimer = null;
        this._attachTimer = null;
        this._settleTimer = null;
    }

    _wrapper() {
        return this.template.querySelector('.gtm-col-chooser');
    }

    _trigger() {
        return this.template.querySelector('button[data-trigger]');
    }

    _open() {
        this.isOpen = true;
        this._focusPending = true;
        this._placeOnce = true;
        // The opening click is still bubbling to document: attach the outside-click
        // listener only AFTER it has finished, and ignore focusout until the
        // programmatic focus move has settled (see renderedCallback).
        this._settling = true;
        this._detachDocClick();
        this._clearTimers();
        this._attachTimer = setTimeout(() => {
            this._attachTimer = null;
            if (this.isOpen) this._attachDocClick();
        }, 0);
        // One popover at a time (chooser side of the pair; the filter bar closes on
        // the outside click / focusout this open produces).
        document.dispatchEvent(new CustomEvent(OPEN_EVENT, { detail: { source: this } }));
    }

    _close(returnFocus) {
        if (!this.isOpen) return;
        this.isOpen = false;
        this.hint = '';
        this._focusPending = false;
        this._refocusPending = false;
        this._regroupPending = false;
        this._placeOnce = false;
        this._settling = false;
        this._pointerDown = false;
        this._detachDocClick();
        this._clearTimers();
        if (returnFocus) {
            const t = this._trigger();
            if (t && typeof t.focus === 'function') t.focus();
        }
    }

    _attachDocClick() {
        this._detachDocClick();
        this._docClick = (event) => {
            // Primary signal: a bubbling handler in OUR shadow saw this interaction pass
            // through the wrapper (independent of retargeting / composedPath).
            if (this._insideInteraction) return;
            const wrapper = this._wrapper();
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            const inside =
                (wrapper && path.includes(wrapper)) ||
                event.target === this.template.host ||
                (wrapper && wrapper.contains(event.target));
            if (inside) return;
            // Never close synchronously: a real event's activation behaviour (the
            // input's change) runs after this listener and must find the input in the DOM.
            if (this._outsideTimer) clearTimeout(this._outsideTimer);
            this._outsideTimer = setTimeout(() => {
                this._outsideTimer = null;
                if (!this._insideInteraction && this.isOpen) this._close(false);
            }, 0);
        };
        document.addEventListener('click', this._docClick);
    }

    _detachDocClick() {
        if (this._docClick) {
            document.removeEventListener('click', this._docClick);
            this._docClick = null;
        }
    }

    // One-shot viewport clamp on open (measured once, no resize observing). The
    // popover is right-anchored, so a shift is applied through `right`.
    _clamp(pop) {
        const cw = document.documentElement.clientWidth;
        if (!cw) return;
        const rect = pop.getBoundingClientRect();
        let shift = 0;
        if (rect.right > cw - EDGE) shift = -(rect.right - (cw - EDGE));
        if (rect.left + shift < EDGE) shift = EDGE - rect.left;
        if (shift) pop.style.right = `${-shift}px`;
    }

    handleTriggerClick() {
        if (this.isOpen) {
            this._close(false);
        } else {
            this._open();
        }
    }

    handleKeydown(event) {
        this._markInside();
        if (event.key !== 'Escape' || !this.isOpen) return;
        event.stopPropagation();
        this._close(true);
    }

    // Pointer down inside the popover: browsers move focus onto a container div (or
    // drop it) BEFORE the click completes. Suppress any focus-based close until the
    // click has finished so the input can toggle.
    _markInside() {
        this._insideInteraction = true;
        if (this._insideTimer) clearTimeout(this._insideTimer);
        this._insideTimer = setTimeout(() => {
            this._insideTimer = null;
            this._insideInteraction = false;
        }, 0);
    }

    handlePointerDown() {
        this._markInside();
        if (!this.isOpen) return;
        this._pointerDown = true;
        if (this._pointerTimer) clearTimeout(this._pointerTimer);
        this._pointerTimer = setTimeout(() => {
            this._pointerTimer = null;
            this._pointerDown = false;
        }, 500);
    }

    handleWrapperClick() {
        this._markInside();
        if (!this._pointerDown) return;
        if (this._pointerTimer) clearTimeout(this._pointerTimer);
        this._pointerTimer = setTimeout(() => {
            this._pointerTimer = null;
            this._pointerDown = false;
        }, 0);
    }

    // The ONLY focus-based close: focus moved to a known Element that is neither the
    // popover's own content nor its own trigger (Tab away). A null relatedTarget,
    // document/window, focus inside the popover, and any focusout during an inside
    // pointer interaction never close it.
    handleFocusOut(event) {
        if (!this.isOpen || this._settling || this._pointerDown) return;
        const next = event.relatedTarget;
        if (!next || next.nodeType !== 1 || next === this.template.host) return;
        const pop = this.template.querySelector('[data-pop]');
        const trigger = this._trigger();
        if ((pop && (pop === next || pop.contains(next))) || next === trigger) return;
        this._close(false);
    }

    renderedCallback() {
        if (!this.isOpen) return;
        const pop = this.template.querySelector('[data-pop]');
        if (!pop) return;
        if (this._focusPending) {
            this._focusPending = false;
            const first = pop.querySelector('lightning-checkbox-group');
            // focus() on the base component is UNVERIFIED: guard, fall back to the dialog.
            if (first && typeof first.focus === 'function') first.focus();
            if (!this.template.activeElement && typeof pop.focus === 'function') pop.focus();
            this._settleTimer = setTimeout(() => {
                this._settleTimer = null;
                this._settling = false;
            }, 0);
        }
        if (this._placeOnce) {
            this._placeOnce = false;
            this._clamp(pop);
        }
        // The group was re-created by the last-column guard: put focus back on it.
        if (this._regroupPending) {
            this._regroupPending = false;
            const g = pop.querySelector('lightning-checkbox-group');
            if (g && typeof g.focus === 'function') g.focus();
            if (!this.template.activeElement && typeof pop.focus === 'function') pop.focus();
        }
        // Reset just became disabled: a disabled button drops focus, so keep it inside.
        if (this._refocusPending && this.resetDisabled) {
            this._refocusPending = false;
            const g = pop.querySelector('lightning-checkbox-group');
            if (g && typeof g.focus === 'function') g.focus();
            if (!this.template.activeElement && typeof pop.focus === 'function') pop.focus();
        }
    }
    // ==== END POPOVER MECHANICS =====================================================
}
