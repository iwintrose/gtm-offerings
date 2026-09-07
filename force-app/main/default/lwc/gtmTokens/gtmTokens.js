import { LightningElement } from 'lwc';

// CSS-only module. Never placed on a page -- its only purpose is
// `@import 'c/gtmTokens';` from another component's own stylesheet. See the
// comment in gtmTokens.css for why the tokens have to be imported per
// component rather than set once on a shared shell.
export default class GtmTokens extends LightningElement {}
