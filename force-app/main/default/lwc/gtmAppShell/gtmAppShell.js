import { LightningElement, track } from 'lwc';

export default class GtmAppShell extends LightningElement {
  @track currentView = 'offeringChooser';
  @track selectedOffering = null;
  @track selectedIndustry = null;

  connectedCallback() {
    this.handleRouting();
    window.addEventListener('hashchange', () => this.handleRouting());
  }

  handleRouting() {
    const hash = window.location.hash.slice(1) || 'offerings';

    switch (hash) {
      case 'offerings':
        this.currentView = 'offeringChooser';
        break;
      case 'industry':
        this.currentView = 'chooseIndustry';
        break;
      case 'configurator':
        this.currentView = 'maConfigurator';
        break;
      default:
        this.currentView = 'offeringChooser';
    }
  }

  get showOfferingChooser() {
    return this.currentView === 'offeringChooser';
  }

  get showChooseIndustry() {
    return this.currentView === 'chooseIndustry';
  }

  get showMaConfigurator() {
    return this.currentView === 'maConfigurator';
  }

  handleNavigate(event) {
    const { view, industry } = event.detail;

    if (view === 'offering') {
      this.currentView = 'chooseIndustry';
      window.location.hash = '#industry';
    } else if (view === 'configurator') {
      this.currentView = 'maConfigurator';
      const industryParam = industry ? `industry=${industry}` : 'industry=null';
      window.location.hash = `#configurator&${industryParam}`;
    }
  }

  disconnectedCallback() {
    window.removeEventListener('hashchange', () => this.handleRouting());
  }
}