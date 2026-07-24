import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import InvoicePreviewModal from 'c/invoicePreviewModal';
import RateConEmailModal from 'c/rateConEmailModal';
import PingDriverModal from 'c/pingDriverModal';
import getLoadPage from '@salesforce/apex/DispatchConsoleController.getLoadPage';

export default class DispatchDocuments extends NavigationMixin(LightningElement) {
    @api stateCode;

    @track loads = [];
    @track summary = {};
    @track totalRecords = 0;
    @track activeView = 'all';
    @track searchKey = '';
    @track selectedDocumentId;
    @track currentPage = 1;
    @track isLoading = false;
    @track errorMessage;

    pageSize = 10;
    searchTimer;
    requestSequence = 0;
    localStateCode = '';

    connectedCallback() {
        this.localStateCode = this.stateCode || '';
        this.fetchPage('first', true);
    }

    renderedCallback() {
        const incomingState = this.stateCode || '';
        if (incomingState !== this.localStateCode) {
            this.localStateCode = incomingState;
            this.resetAndFetch(true);
        }
    }

    disconnectedCallback() {
        if (this.searchTimer) {
            window.clearTimeout(this.searchTimer);
        }
    }

    handleViewChange(event) {
        this.activeView = event.currentTarget.dataset.view || 'all';
        this.selectedDocumentId = undefined;
        this.resetAndFetch(false);
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
        this.selectedDocumentId = undefined;
        if (this.searchTimer) {
            window.clearTimeout(this.searchTimer);
        }
        this.searchTimer = window.setTimeout(() => this.resetAndFetch(false), 400);
    }

    handleClearFilters() {
        this.activeView = 'all';
        this.searchKey = '';
        this.selectedDocumentId = undefined;
        this.resetAndFetch(false);
    }

    handleFirstPage() {
        this.fetchPage('first', false);
    }

    handlePreviousPage() {
        this.fetchPage('previous', false);
    }

    handleNextPage() {
        this.fetchPage('next', false);
    }

    handleLastPage() {
        this.fetchPage('last', false);
    }

    handleRefresh() {
        this.resetAndFetch(true);
    }

    resetAndFetch(includeSummary = false) {
        this.currentPage = 1;
        this.fetchPage('first', includeSummary);
    }

    async fetchPage(direction = 'first', includeSummary = false) {
        const firstRecord = this.loads.length ? this.loads[0] : null;
        const lastRecord = this.loads.length ? this.loads[this.loads.length - 1] : null;
        const cursorRecord = direction === 'previous' ? firstRecord : lastRecord;
        const requestId = ++this.requestSequence;
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getLoadPage({
                context: 'documents',
                stateCode: this.localStateCode || '',
                searchKey: this.searchKey || '',
                viewName: this.activeView || 'all',
                statusFilter: 'All',
                pageSize: this.pageSize,
                cursorCreatedDate: cursorRecord?.CreatedDate || null,
                cursorId: cursorRecord?.Id || null,
                direction,
                includeSummary
            });
            if (requestId !== this.requestSequence) {
                return;
            }
            this.loads = result?.records || [];
            this.totalRecords = result?.totalCount || 0;
            if (result?.summary) {
                this.summary = result.summary;
            }
            if (direction === 'next') {
                this.currentPage = Math.min(this.totalPages, this.currentPage + 1);
            } else if (direction === 'previous') {
                this.currentPage = Math.max(1, this.currentPage - 1);
            } else if (direction === 'last') {
                this.currentPage = this.totalPages;
            } else {
                this.currentPage = 1;
            }
            this.selectedDocumentId = this.loads.length ? this.loads[0].Id : undefined;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load documents.';
        } finally {
            if (requestId === this.requestSequence) {
                this.isLoading = false;
            }
        }
    }

    handleRowSelect(event) {
        this.selectedDocumentId = event.currentTarget.dataset.id;
    }

    handleOpenLoad(event) {
        event.stopPropagation();

        const loadId = event.currentTarget.dataset.id;

        this.openLoad(loadId);
    }

    handleOpenSelectedLoad() {
        if (!this.selectedDocument?.Id) {
            return;
        }

        this.openLoad(this.selectedDocument.Id);
    }

    async handleEmailSelectedCarrier() {
    if (!this.selectedDocument?.Id) {
        return;
    }

    if (!this.selectedDocument?.carrierEmail) {
        this.showToast(
            'Missing Carrier Email',
            'No carrier email is available for this load.',
            'error'
        );
        return;
    }

    const result = await RateConEmailModal.open({
        size: 'large',
        description: 'Send RateCon PDF to carrier.',
        loadId: this.selectedDocument.Id,
        loadName: this.selectedDocument.Name,
        carrierName: this.selectedDocument.carrierName,
        carrierEmail: this.selectedDocument.carrierEmail
    });

    if (result?.action === 'sent') {
        this.showToast(
            'RateCon Sent',
            `RateCon PDF was sent to ${this.selectedDocument.carrierEmail}.`,
            'success'
        );
        return;
    }

    if (result?.action === 'error') {
        this.showToast(
            'Email Error',
            result.message || 'Unable to send RateCon email.',
            'error'
        );
    }
}

async handlePingSelectedDriver() {
    const load = this.selectedDocument;

    if (!load?.Id) {
        return;
    }

    const result = await PingDriverModal.open({
        size: 'small',
        description: 'Send the driver portal link by SMS.',
        loadId: load.Id,
        loadName: load.Name,
        driverId: load.FreightTM__Driver__c,
        driverName: load.driverName,
        driverPhone: load.Driver_Phone_Number__c,
        driverCarrier: load.Driver_Phone_Carrier__c,
        portalLink: load.Driver_Portal_Link__c
    });

    if (result?.action === 'sent') {
        this.showToast(
            'Driver Ping Sent',
            `The portal link was queued for ${result.phoneNumber}.`,
            'success'
        );

        this.handleRefresh();
        return;
    }

    if (result?.action === 'error') {
        this.showToast(
            'Ping Driver Error',
            result.message || 'Unable to send the driver portal link.',
            'error'
        );
    }
}

    async handleGenerateInvoice() {
    if (!this.selectedDocument?.Id) {
        return;
    }

    await this.openInvoicePreview(this.selectedDocument);
}

async handleGenerateInvoiceFromRow(event) {
    event.stopPropagation();

    const loadId = event.currentTarget.dataset.id;
    const load = this.documentRows.find((row) => row.Id === loadId);

    if (!load) {
        return;
    }

    await this.openInvoicePreview(load);
}

async openInvoicePreview(load) {
    const result = await InvoicePreviewModal.open({
        size: 'large',
        description: 'Preview invoice PDF before saving it to load files.',
        loadId: load.Id,
        loadName: load.Name
    });

    if (result?.action === 'saved') {
        this.showToast(
            'Invoice Saved',
            `Invoice PDF was saved to ${load.Name} files.`,
            'success'
        );

        this.handleRefresh();
        return;
    }

    if (result?.action === 'error') {
        this.showToast(
            'Invoice Error',
            result.message || 'Unable to save invoice PDF.',
            'error'
        );
    }
}

showToast(title, message, variant) {
    this.dispatchEvent(
        new ShowToastEvent({
            title,
            message,
            variant
        })
    );
}

    openLoad(loadId) {
        if (!loadId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: loadId,
                objectApiName: 'FreightTM__Load__c',
                actionName: 'view'
            }
        });
    }

    get documentRows() {
        return (this.loads || []).map((load) => {
            const podReceived = load.POD_Received__c === true;

            const billStatus = load.FreightTM__Bill_Status__c || 'Bill status unavailable';
            const invoiceStatus = load.FreightTM__Invoice_Status__c || 'Invoice status unavailable';

            const pickupCity = load.FreightTM__Pickup_City__c || 'Origin';
            const deliveryCity = load.FreightTM__Delivery_City__c || 'Destination';

            const pickupState = load.FreightTM__Pickup_State__c || '';
            const deliveryState = load.FreightTM__Delivery_State__c || '';

            const customerName =
                load.FreightTM__Customer__r?.Name ||
                load.FreightTM__Account__r?.Name ||
                load.Customer__r?.Name ||
                'Customer unavailable';

            const carrierName = load.FreightTM__Carrier_Obj__r?.Name || 'Unassigned';

            const carrierEmail =
                load.FreightTM__Carrier_Obj__r?.FreightTM__Email__c ||
                load.FreightTM__Carrier_Obj__r?.Email__c ||
                load.FreightTM__Carrier_Obj__r?.Email ||
                '';
            const driverName =
            load.FreightTM__Driver__r?.Name ||
            'Unassigned';    

            const docStatus = this.getDocumentStatus(load, podReceived, billStatus, invoiceStatus);
            const isSelected = load.Id === this.selectedDocumentId;

            return {
                ...load,
                customerName,
                driverName,
                carrierName,
                carrierEmail,
                carrierEmailLabel: carrierEmail || 'No email',
                route: `${pickupCity} → ${deliveryCity}`,
                routeStates: `${pickupState || '—'} → ${deliveryState || '—'}`,
                podLabel: podReceived ? 'Received' : 'Missing',
                billStatus,
                invoiceStatus,
                deliveryDateLabel: this.formatDate(load.FreightTM__Delivery_Date__c),
                statusType: docStatus.type,
                statusLabel: docStatus.label,
                statusClass: `status-badge ${docStatus.type}`,
                rowClass: `document-row ${docStatus.type} ${isSelected ? 'selected-row' : ''}`
            };
        });
    }

    getDocumentStatus(load, podReceived, billStatus, invoiceStatus) {
        const bill = (billStatus || '').toLowerCase();
        const invoice = (invoiceStatus || '').toLowerCase();

        if (!podReceived) {
            return {
                type: 'missing',
                label: 'Missing POD'
            };
        }

        if (
            bill.includes('pod received') ||
            bill.includes('bill/pod received') ||
            invoice.includes('ready') ||
            invoice.includes('approved') ||
            invoice.includes('invoiced')
        ) {
            return {
                type: 'ready',
                label: 'Ready to Invoice'
            };
        }

        if (
            bill.includes('variance') ||
            bill.includes('claim') ||
            invoice.includes('hold') ||
            invoice.includes('rejected')
        ) {
            return {
                type: 'waiting',
                label: 'Needs Review'
            };
        }

        return {
            type: 'complete',
            label: 'Complete'
        };
    }

    get filteredDocumentRows() {
        return this.documentRows;
    }

    matchesActiveView(doc) {
        if (this.activeView === 'missingPod') {
            return doc.statusType === 'missing';
        }

        if (this.activeView === 'readyToInvoice') {
            return doc.statusType === 'ready';
        }

        if (this.activeView === 'waiting') {
            return doc.statusType === 'waiting';
        }

        if (this.activeView === 'complete') {
            return doc.statusType === 'complete';
        }

        return true;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get pageNumber() {
        return Math.min(this.currentPage, this.totalPages);
    }

    get paginatedDocumentRows() {
        return this.documentRows;
    }

    get pageRangeLabel() {
        if (!this.totalRecords) {
            return '0 records';
        }
        const start = ((this.pageNumber - 1) * this.pageSize) + 1;
        const end = Math.min(start + this.loads.length - 1, this.totalRecords);
        return `Showing ${start}-${end} of ${this.totalRecords}`;
    }

    get previousDisabled() {
        return this.isLoading || this.pageNumber <= 1;
    }

    get nextDisabled() {
        return this.isLoading || this.pageNumber >= this.totalPages;
    }

    get selectedDocument() {
        if (this.selectedDocumentId) {
            return this.documentRows.find((doc) => doc.Id === this.selectedDocumentId);
        }

        return this.paginatedDocumentRows.length ? this.paginatedDocumentRows[0] : null;
    }

    get selectedCarrierEmailDisabled() {
        return !this.selectedDocument?.carrierEmail;
    }

    get hasDocuments() {
        return this.loads.length > 0;
    }

    get totalCount() {
        return this.summary?.totalLoads || 0;
    }

    get missingPodCount() {
        return this.summary?.missingPodCount || 0;
    }

    get readyToInvoiceCount() {
        return this.summary?.readyToInvoiceCount || 0;
    }

    get waitingCount() {
        return this.summary?.waitingDocumentCount || 0;
    }

    get completeCount() {
        return this.summary?.completeDocumentCount || 0;
    }

    get documentCountLabel() {
        return `${this.totalCount} document records loaded`;
    }

    get filteredCountLabel() {
        return `${this.totalRecords} found`;
    }

    get allViewClass() {
        return this.activeView === 'all' ? 'priority-button active' : 'priority-button';
    }

    get missingViewClass() {
        return this.activeView === 'missingPod' ? 'priority-button active danger' : 'priority-button';
    }

    get readyViewClass() {
        return this.activeView === 'readyToInvoice' ? 'priority-button active blue' : 'priority-button';
    }

    get waitingViewClass() {
        return this.activeView === 'waiting' ? 'priority-button active warning' : 'priority-button';
    }

    get completeViewClass() {
        return this.activeView === 'complete' ? 'priority-button active success' : 'priority-button';
    }

    formatDate(value) {
        if (!value) {
            return 'Unavailable';
        }

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return 'Unavailable';
        }

        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric'
        }).format(date);
    }
}