import { LightningElement } from 'lwc';
import redirectUrl from '@salesforce/label/c.GTM_Home_Redirect_Url';

/**
 * The bare /gtm home page has nothing of its own to show -- the only
 * public page on this site is the Configurator, reached through a specific
 * saved link. A visitor who lands here anyway (bookmark, typo, someone
 * poking at the domain) gets sent somewhere real instead of a blank page.
 *
 * Where "somewhere real" points is a Custom Label
 * (GTM_Home_Redirect_Url), editable in Setup > Custom Labels without a
 * metadata deploy -- change the destination there, not in code.
 */
export default class GtmHomeRedirect extends LightningElement {
    connectedCallback() {
        if (redirectUrl) {
            window.location.replace(redirectUrl);
        }
    }
}
