import { LightningElement, track } from 'lwc';

export default class DispatchContainer extends LightningElement {
    @track activeTab = 'loadBoard';
    @track stateCode = '';

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleStateChange(event) {
        this.stateCode = event.detail.stateCode || '';
    }

    get pageTitle() {
        if (this.activeTab === 'loadBoard') {
            return 'Load Board';
        }
        if (this.activeTab === 'assignment') {
            return 'Assignment Center';
        }
        if (this.activeTab === 'documents') {
            return 'Documents Queue';
        }
        if (this.activeTab === 'margin') {
            return 'Profitability';
        }
        return 'Dispatch Console';
    }

    get pageSubtitle() {
        if (this.activeTab === 'loadBoard') {
            return 'Monitor active loads, exceptions, invoice readiness, and operational status.';
        }
        if (this.activeTab === 'assignment') {
            return 'Match trucks, drivers, carriers, and loads by operating state.';
        }
        if (this.activeTab === 'documents') {
            return 'Track PODs, billing documents, invoice blockers, and document readiness.';
        }
        if (this.activeTab === 'margin') {
            return 'Review profitability, margin risk, and financial performance.';
        }
        return '';
    }

    get isLoadBoardTab() {
        return this.activeTab === 'loadBoard';
    }

    get isAssignmentTab() {
        return this.activeTab === 'assignment';
    }

    get isDocumentsTab() {
        return this.activeTab === 'documents';
    }

    get isMarginTab() {
        return this.activeTab === 'margin';
    }

    get loadBoardTabClass() {
        return this.activeTab === 'loadBoard' ? 'tab active' : 'tab';
    }

    get assignmentTabClass() {
        return this.activeTab === 'assignment' ? 'tab active' : 'tab';
    }

    get documentsTabClass() {
        return this.activeTab === 'documents' ? 'tab active' : 'tab';
    }

    get marginTabClass() {
        return this.activeTab === 'margin' ? 'tab active' : 'tab';
    }
}