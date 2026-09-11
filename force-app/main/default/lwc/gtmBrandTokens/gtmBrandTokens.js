import { LightningElement } from 'lwc';

/**
 * CSS-only shared module. `gtmStory` (and any other component) pulls this
 * bundle in purely for its `--ps-*` custom properties via
 * `@import 'c/gtmBrandTokens';` in CSS -- nothing here is ever imported from
 * JS or placed on a page. This class exists only so the bundle satisfies the
 * Metadata API's LightningComponentBundle shape (a body + a -meta.xml); it is
 * never instantiated.
 */
export default class GtmBrandTokens extends LightningElement {}
