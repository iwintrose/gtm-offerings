import { LightningElement, api } from 'lwc';

const DEFAULT_PRESETS = [
    { value: '7', label: 'Last 7 days' },
    { value: '30', label: 'Last 30 days' },
    { value: '90', label: 'Last 90 days' }
];
const ANY = '';
const CUSTOM = '__custom__';
const MORE = '__more__';
const SEARCH_THRESHOLD = 8;
const EDGE = 8; // px kept clear at the viewport edge
const STORAGE_PREFIX = 'gtm.filterbar.added.';
const MAX_ADDED = 20;
// Tier 2 of the memory fallback: survives the bar being destroyed and re-created
// during the page's life even when localStorage is blocked.
const SESSION_ADDED = {};

function readRemembered(storageKey) {
    if (!storageKey) return [];
    try {
        const raw = window.localStorage.getItem(STORAGE_PREFIX + storageKey);
        // Storage works: trust it, including "nothing stored yet".
        if (raw === null || raw === undefined) return [];
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
            return parsed.filter((k) => typeof k === 'string' && k).slice(0, MAX_ADDED);
        }
    } catch (e) {
        // blocked or private storage, bad JSON: fall through to the in-memory map
    }
    return (SESSION_ADDED[storageKey] || []).slice(0, MAX_ADDED);
}

function writeRemembered(storageKey, keys) {
    if (!storageKey) return;
    const list = Array.from(new Set(keys)).slice(-MAX_ADDED);
    SESSION_ADDED[storageKey] = list;
    try {
        window.localStorage.setItem(STORAGE_PREFIX + storageKey, JSON.stringify(list));
    } catch (e) {
        // swallowed: the in-memory state is already right for this session
    }
}

/**
 * Presentation-only, config-driven filter bar (compact, Jira-style): one row of
 * filter buttons, each opening a popover whose contents are base lightning-*
 * components. No Apex, no domain vocabulary. Contract:
 * docs/architecture/gtm-filter-bar.md (Addendum B).
 */
export default class GtmFilterBar extends LightningElement {
    _filters = [];
    _values = {};
    _storageKey = '';
    // Keys of `more` filters the user has added to the row (component state).
    _addedKeys = [];
    _announce = '';
    _focusMorePending = false;

    @api
    get filters() {
        return this._filters;
    }
    set filters(v) {
        this._filters = v;
        this._absorbActive();
    }

    @api
    get values() {
        return this._values;
    }
    set values(v) {
        this._values = v;
        this._absorbActive();
    }

    /** Optional: remembers which `more` filters were added, per browser (keys only). */
    @api
    get storageKey() {
        return this._storageKey;
    }
    set storageKey(v) {
        const next = typeof v === 'string' ? v : '';
        if (next === this._storageKey) return;
        this._storageKey = next;
        this._loadRemembered();
    }
    @api resultCount;
    @api resultLabel = '';
    @api label = 'Filters';
    @api variant = 'default';

    // Unsaved half-entered custom ranges, and keys where Custom is chosen.
    _drafts = {};
    _customOpen = {};
    // Popover state: the open slot key (a filter key or MORE), per-filter search text.
    _openKey = null;
    _search = {};
    _focusPending = false;
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

    connectedCallback() {
        this._loadRemembered();
    }

    _loadRemembered() {
        if (!this._storageKey) return;
        const remembered = readRemembered(this._storageKey);
        const merged = Array.from(new Set([...remembered, ...this._addedKeys]));
        if (merged.length !== this._addedKeys.length) this._addedKeys = merged;
    }

    /** A `more` filter with an active value is always on the row; keep it there
     *  (in memory only, never written) so it survives Clear filters. */
    _absorbActive() {
        const add = (this._filters || [])
            .filter((f) => f && f.more && !this._isEmpty(f, (this._values || {})[f.key]))
            .map((f) => f.key)
            .filter((k) => !this._addedKeys.includes(k));
        if (add.length) this._addedKeys = [...this._addedKeys, ...add];
    }

    _persistAdded() {
        writeRemembered(this._storageKey, this._addedKeys);
    }

    disconnectedCallback() {
        this._detachDocClick();
        this._clearTimers();
    }

    _clearTimers() {
        [this._pointerTimer, this._attachTimer, this._settleTimer, this._insideTimer, this._outsideTimer].forEach((t) => t && clearTimeout(t));
        this._insideTimer = null;
        this._outsideTimer = null;
        this._insideInteraction = false;
        this._pointerTimer = null;
        this._attachTimer = null;
        this._settleTimer = null;
    }

    get isCompact() {
        return this.variant === 'compact';
    }

    get rootClass() {
        return (
            'gtm-filter-bar slds-grid slds-wrap slds-grid_vertical-align-center slds-grid_align-end ' +
            (this.isCompact ? 'gtm-filter-bar--compact' : 'gtm-filter-bar--default')
        );
    }

    get hasCount() {
        return typeof this.resultCount === 'number' && !Number.isNaN(this.resultCount);
    }

    get countText() {
        return `${this.resultCount}${this.resultLabel ? ' ' + this.resultLabel : ''}`;
    }

    get hasActive() {
        return (this.filters || []).some((f) => !this._isEmpty(f, this._val(f.key)));
    }

    _val(key) {
        return (this.values || {})[key];
    }

    _isEmpty(f, v) {
        if (v === undefined || v === null || v === '' || v === false) return true;
        if (Array.isArray(v)) return v.length === 0;
        if (f.type === 'date-range' && typeof v === 'object') return !(v.from && v.to);
        return false;
    }

    _optionsWithCounts(options) {
        return (options || []).map((o) => ({
            value: String(o.value),
            // Optional `hint` says what the option filters when the column cannot show it
            // (list label only; the trigger text uses the plain label).
            label:
                (o.hint ? `${o.label}: ${o.hint}` : o.label) +
                (typeof o.count === 'number' ? ` (${o.count})` : '')
        }));
    }

    // Value label WITHOUT the "(n)" count, for the trigger text.
    _plainLabel(f, value) {
        const opts = f.options || [];
        const find = (v) => {
            const o = opts.find((x) => String(x.value) === String(v));
            return o ? o.label : String(v);
        };
        if (f.type === 'date-range') {
            if (value && typeof value === 'object') return `${value.from} to ${value.to}`;
            const p = (opts.length ? opts : DEFAULT_PRESETS).find(
                (x) => String(x.value) === String(value)
            );
            return p ? p.label : String(value);
        }
        return find(value);
    }

    // { active, text, aria } for one filter (Addendum B.5 table).
    _summary(f) {
        const v = this._val(f.key);
        if (this._isEmpty(f, v)) {
            return { active: false, text: f.label, aria: `${f.label}, no filter applied` };
        }
        if (f.type === 'toggle') {
            const t = `${f.label}: On`;
            return { active: true, text: t, aria: t };
        }
        if (Array.isArray(v) && v.length > 1) {
            const names = v.map((x) => this._plainLabel(f, x));
            return {
                active: true,
                text: `${f.label}: ${v.length}`,
                aria: `${f.label}: ${v.length} selected, ${names.join(', ')}`
            };
        }
        const one = Array.isArray(v) ? v[0] : v;
        const t = `${f.label}: ${this._plainLabel(f, one)}`;
        return { active: true, text: t, aria: t };
    }

    // Content-stable identities: the bar is re-rendered by its parent with NEW
    // filters/values objects (equal content) on many events. Handing a base
    // component a NEW options/value array makes it re-render its inputs, which can
    // replace the input between mousedown and click so no `change` ever fires.
    _memo = {};
    _stable(name, val) {
        const sig = JSON.stringify(val);
        const hit = this._memo[name];
        if (hit && hit.sig === sig) return hit.val;
        this._memo[name] = { sig, val };
        return val;
    }

    _filtered(f) {
        const all = this._optionsWithCounts(f.options);
        // serverSearch: the consumer narrows the options itself (filtersearch event).
        if (f.serverSearch) return all;
        const text = (this._search[f.key] || '').trim().toLowerCase();
        return text ? all.filter((o) => String(o.label).toLowerCase().includes(text)) : all;
    }

    _section(f, showTitle) {
        const v = this._val(f.key);
        const isMulti = f.type === 'chips' && !!f.multi;
        const isSingle = (f.type === 'chips' && !f.multi) || f.type === 'select';
        const isToggle = f.type === 'toggle';
        const isDateRange = f.type === 'date-range';
        const listy = isMulti || isSingle;
        const view = {
            key: f.key,
            label: f.label,
            showTitle,
            isMulti,
            isSingle,
            isToggle,
            isDateRange,
            checked: v === true,
            searchable: listy && (!!f.searchable || (f.options || []).length > SEARCH_THRESHOLD),
            searchLabel: `Filter ${f.label} options`,
            searchValue: this._search[f.key] || ''
        };
        if (listy) {
            const opts = this._filtered(f);
            view.hasOptions = opts.length > 0 || f.type === 'select';
            if (isMulti) {
                view.options = this._stable(`${f.key}:o`, opts);
                view.value = this._stable(`${f.key}:v`, Array.isArray(v) ? v.map(String) : []);
            } else {
                view.options = this._stable(
                    `${f.key}:o`,
                    f.type === 'select' ? [{ value: ANY, label: 'Any' }, ...opts] : opts
                );
                view.value = v == null ? ANY : String(v);
            }
        }
        if (isDateRange) {
            const draft = this._drafts[f.key] || {};
            const isObj = v && typeof v === 'object';
            const custom = this._customOpen[f.key] || isObj;
            view.options = this._stable(`${f.key}:o`, [
                { value: ANY, label: 'Any time' },
                ...this._optionsWithCounts(f.options && f.options.length ? f.options : DEFAULT_PRESETS),
                { value: CUSTOM, label: 'Custom range' }
            ]);
            view.value = custom ? CUSTOM : v == null ? ANY : String(v);
            view.showCustom = !!custom;
            view.from = isObj ? v.from : draft.from || '';
            view.to = isObj ? v.to : draft.to || '';
        }
        return view;
    }

    _slot(key, filters, isMore, extra = {}) {
        const open = this._openKey === key;
        let text;
        let aria;
        let active;
        let popLabel;
        if (isMore) {
            const n = extra.hidden;
            active = extra.added > 0;
            text = `More (${n})`;
            aria = `More (${n}) filters, ${n} not shown, ${extra.added} added`;
            popLabel = 'Add filters';
        } else {
            const s = this._summary(filters[0]);
            active = s.active;
            text = s.text;
            aria = s.aria;
            popLabel = filters[0].label;
        }
        return {
            key,
            isMore,
            removable: !isMore && !!filters[0].more,
            removeLabel: isMore ? '' : `Remove ${filters[0].label} filter`,
            popId: `gtm-filter-bar-pop-${key}`,
            popLabel,
            open,
            expanded: open ? 'true' : 'false',
            triggerText: text,
            triggerAria: aria,
            wrapClass:
                'gtm-filter-bar__item slds-dropdown-trigger slds-dropdown-trigger_click slds-m-bottom_xx-small ' +
                (this.isCompact ? 'slds-m-right_xx-small' : 'slds-m-right_x-small') +
                (open ? ' slds-is-open' : ''),
            triggerClass:
                'slds-button slds-button_neutral gtm-filter-bar__trigger' +
                (active && !isMore ? ' gtm-filter-bar__trigger--active' : ''),
            popClass:
                'slds-dropdown gtm-filter-bar__pop' + (isMore ? ' gtm-filter-bar__pop--more' : ''),
            sections: open && !isMore ? filters.map((f) => this._section(f, false)) : [],
            moreItems: open && isMore ? this._moreItems() : []
        };
    }

    /** A list filter with fewer than two options offers no choice: hide it (row and
     *  More list) unless a value is set, e.g. from a deep link. */
    _hasChoice(f) {
        if (f.type === 'toggle' || f.type === 'date-range' || f.serverSearch) return true;
        return (f.options || []).length >= 2;
    }

    _usable(f) {
        return this._hasChoice(f) || !this._isEmpty(f, this._val(f.key));
    }

    _isShown(f) {
        return !f.more || this._addedKeys.includes(f.key) || !this._isEmpty(f, this._val(f.key));
    }

    _moreItems() {
        return (this.filters || [])
            .filter((f) => f.more && this._usable(f))
            .map((f) => {
                const active = !this._isEmpty(f, this._val(f.key));
                return {
                    key: f.key,
                    label: f.label,
                    checked: this._isShown(f),
                    disabled: active,
                    help: active
                };
            });
    }

    get slots() {
        const all = (this.filters || []).filter((f) => this._usable(f));
        const slots = all.filter((f) => this._isShown(f)).map((f) => this._slot(f.key, [f], false));
        const more = all.filter((f) => f.more);
        const hidden = more.filter((f) => !this._isShown(f)).length;
        if (hidden > 0) {
            slots.push(this._slot(MORE, more, true, { hidden, added: more.length - hidden }));
        }
        return slots;
    }

    get announcement() {
        return this._announce;
    }

    _findFilter(key) {
        return (this.filters || []).find((f) => f.key === key);
    }

    _emit(key, value) {
        this.dispatchEvent(new CustomEvent('filterchange', { detail: { key, value } }));
    }

    _key(event) {
        return event.currentTarget.dataset.key;
    }

    // ---- popover open/close, focus, placement -------------------------------

    _wrapper() {
        return this.template.querySelector('.gtm-filter-bar');
    }

    _trigger(key) {
        return this.template.querySelector(`button[data-slot="${key}"]`);
    }

    _open(key) {
        this._openKey = key;
        this._search = {};
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
            if (this._openKey === key) this._attachDocClick();
        }, 0);
    }

    _close(returnFocus) {
        const key = this._openKey;
        if (key === null) return;
        this._openKey = null;
        this._search = {};
        this._focusPending = false;
        this._placeOnce = false;
        this._settling = false;
        this._pointerDown = false;
        this._detachDocClick();
        this._clearTimers();
        if (returnFocus) {
            const t = this._trigger(key);
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
            const key = this._openKey;
            this._outsideTimer = setTimeout(() => {
                this._outsideTimer = null;
                if (!this._insideInteraction && this._openKey === key) this._close(false);
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

    renderedCallback() {
        if (this._focusMorePending) {
            this._focusMorePending = false;
            const t = this.template.querySelector(`button[data-slot="${MORE}"]`) ||
                this.template.querySelector('button[data-slot]');
            if (t && typeof t.focus === 'function') t.focus();
        }
        if (this._openKey === null) return;
        const pop = this.template.querySelector('[data-pop]');
        if (!pop) return;
        if (this._focusPending) {
            this._focusPending = false;
            const first =
                pop.querySelector('lightning-input[data-role="search"]') ||
                pop.querySelector('lightning-checkbox-group, lightning-radio-group, lightning-input');
            // focus() on the base components is UNVERIFIED: guard, fall back to the dialog.
            if (first && typeof first.focus === 'function') first.focus();
            // If focus did not land inside (or focus() is missing), take it on the dialog.
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
    }

    // One-shot viewport clamp on open (measured once, no resize observing). The
    // popover is right-anchored (`right: 0`), so moving it LEFT means a positive
    // `right` offset.
    _clamp(pop) {
        const cw = document.documentElement.clientWidth;
        if (!cw) return;
        const rect = pop.getBoundingClientRect();
        let offset = 0;
        if (rect.right > cw - EDGE) offset = rect.right - (cw - EDGE);
        if (rect.left - offset < EDGE) offset -= EDGE - (rect.left - offset);
        if (offset) pop.style.right = `${offset}px`;
    }

    handleTriggerClick(event) {
        const key = event.currentTarget.dataset.slot;
        if (this._openKey === key) {
            this._close(false);
        } else {
            this._open(key);
        }
    }

    handleKeydown(event) {
        this._markInside();
        if (event.key !== 'Escape' || this._openKey === null) return;
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
        if (this._openKey === null) return;
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
    // open popover's own content nor its own trigger (Tab away, including to a sibling
    // trigger or the Clear filters button in the same bar). A null relatedTarget
    // (focus dropped, re-render, click on a div), document/window, focus inside the
    // popover, and any focusout during an inside pointer interaction never close it.
    handleFocusOut(event) {
        if (this._openKey === null || this._settling || this._pointerDown) return;
        const next = event.relatedTarget;
        if (!next || next.nodeType !== 1 || next === this.template.host) return;
        const pop = this.template.querySelector('[data-pop]');
        const trigger = this._trigger(this._openKey);
        if ((pop && (pop === next || pop.contains(next))) || next === trigger) return;
        this._close(false);
    }

    // ---- change handlers -------------------------------------------------------

    handleSearchChange(event) {
        event.stopPropagation();
        const key = this._key(event);
        const value = event.detail.value || '';
        this._search = { ...this._search, [key]: value };
        const f = this._findFilter(key);
        // Additive: filters with serverSearch also announce the text so the consumer can fetch options.
        if (f && f.serverSearch) {
            this.dispatchEvent(new CustomEvent('filtersearch', { detail: { key, value } }));
        }
    }

    handleMultiChange(event) {
        const key = this._key(event);
        const f = this._findFilter(key);
        if (!f) return;
        // The group emits only the VISIBLE values; keep selections hidden by the search text.
        const visible = this._filtered(f).map((o) => o.value);
        const cur = (Array.isArray(this._val(key)) ? this._val(key) : []).map(String);
        const picked = (event.detail.value || []).map(String);
        const next = [...cur.filter((v) => !visible.includes(v)), ...picked];
        // Canonical option order, not click order.
        const ordered = (f.options || []).map((o) => String(o.value)).filter((v) => next.includes(v));
        this._emit(key, ordered);
    }

    handleSingleChange(event) {
        const key = this._key(event);
        const f = this._findFilter(key);
        if (!f) return;
        const value = event.detail.value || '';
        const cur = this._val(key);
        if (f.type !== 'select' && cur != null && String(cur) === value) {
            this._close(true);
            return;
        }
        this._emit(key, value);
        this._close(true);
    }

    handleToggleChange(event) {
        this._emit(this._key(event), !!event.detail.checked);
    }

    handlePresetChange(event) {
        const key = this._key(event);
        const value = event.detail.value;
        if (value === CUSTOM) {
            this._customOpen = { ...this._customOpen, [key]: true };
            this._drafts = { ...this._drafts, [key]: this._drafts[key] || { from: '', to: '' } };
            return;
        }
        this._customOpen = { ...this._customOpen, [key]: false };
        this._drafts = { ...this._drafts, [key]: { from: '', to: '' } };
        this._emit(key, value || '');
    }

    handleDateChange(event) {
        const key = this._key(event);
        const which = event.currentTarget.dataset.edge; // 'from' | 'to'
        const cur = this._val(key);
        const base =
            cur && typeof cur === 'object'
                ? { from: cur.from, to: cur.to }
                : this._drafts[key] || { from: '', to: '' };
        const draft = { ...base, [which]: event.detail.value || '' };
        this._drafts = { ...this._drafts, [key]: draft };
        if (draft.from && draft.to && draft.from <= draft.to) {
            this._emit(key, { from: draft.from, to: draft.to });
        }
    }

    _announceText(text) {
        this._announce = '';
        // reassigned on the next microtask so an identical message is re-announced
        Promise.resolve().then(() => {
            this._announce = text;
        });
    }

    handleMoreToggle(event) {
        const key = event.currentTarget.dataset.key;
        const f = this._findFilter(key);
        if (!f) return;
        const checked = !!event.detail.checked;
        if (checked) {
            if (!this._addedKeys.includes(key)) this._addedKeys = [...this._addedKeys, key];
            this._persistAdded();
            this._announceText(`${f.label} filter added`);
            // Close More WITHOUT returning focus, then open the new filter's popover.
            this._close(false);
            this._open(key);
            return;
        }
        if (!this._isEmpty(f, this._val(key))) return; // in use: remove with its own x
        this._addedKeys = this._addedKeys.filter((k) => k !== key);
        this._persistAdded();
        this._announceText(`${f.label} filter removed`);
    }

    handleRemove(event) {
        const key = event.currentTarget.dataset.key;
        const f = this._findFilter(key);
        if (!f) return;
        if (!this._isEmpty(f, this._val(key))) {
            let empty = '';
            if (f.type === 'chips' && f.multi) empty = [];
            else if (f.type === 'toggle') empty = false;
            this._emit(key, empty); // never `clear`: a hidden filter must not keep filtering
        }
        this._addedKeys = this._addedKeys.filter((k) => k !== key);
        this._drafts = { ...this._drafts, [key]: { from: '', to: '' } };
        this._customOpen = { ...this._customOpen, [key]: false };
        this._persistAdded();
        if (this._openKey === key) this._close(false);
        this._announceText(`${f.label} filter removed`);
        this._focusMorePending = true;
    }

    /** Return every transient interaction flag/timer to its idle state, so a
     *  rapid open/close/change sequence can never leave the bar wedged. */
    _resetTransient() {
        this._clearTimers();
        this._detachDocClick();
        this._openKey = null;
        this._search = {};
        this._focusPending = false;
        this._focusMorePending = false;
        this._placeOnce = false;
        this._settling = false;
        this._pointerDown = false;
        this._insideInteraction = false;
        this._memo = {};
    }

    handleClearAll() {
        this._drafts = {};
        this._customOpen = {};
        this._resetTransient();
        this.dispatchEvent(new CustomEvent('clear'));
    }
}
