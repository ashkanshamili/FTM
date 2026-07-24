import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import InvoicePreviewModal from 'c/invoicePreviewModal';
import RateConEmailModal from 'c/rateConEmailModal';
import PingDriverModal from 'c/pingDriverModal';
import getLoadPage from '@salesforce/apex/DispatchConsoleController.getLoadPage';

export default class DispatchLoadBoard extends NavigationMixin(LightningElement) {
    @api stateCode;

    @track loads = [];
    @track summary = {};
    @track totalRecords = 0;
    @track searchKey = '';
    @track selectedLoadId;
    @track localStateCode = '';
    @track autoRefreshEnabled = false;
    @track activeView = 'all';
    @track currentPage = 1;
    @track isLoading = false;
    @track errorMessage;
    @track lastRefreshedAt = '';

    pageSize = 10;
    refreshInterval;
    searchTimer;
    requestSequence = 0;

    connectedCallback() {
        this.localStateCode = this.stateCode || '';
        this.fetchPage('first', true);
    }

    renderedCallback() {
        const incomingState = this.stateCode || '';
        if (incomingState !== this.localStateCode) {
            this.localStateCode = incomingState;
            this.resetAndFetch();
        }
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
        if (this.searchTimer) {
            window.clearTimeout(this.searchTimer);
        }
    }

    get stateOptions() {
        return [
            { label: 'All States / Provinces', value: '' },
            { label: 'AL', value: 'AL' },
            { label: 'AK', value: 'AK' },
            { label: 'AZ', value: 'AZ' },
            { label: 'AR', value: 'AR' },
            { label: 'CA', value: 'CA' },
            { label: 'CO', value: 'CO' },
            { label: 'CT', value: 'CT' },
            { label: 'DC', value: 'DC' },
            { label: 'DE', value: 'DE' },
            { label: 'FL', value: 'FL' },
            { label: 'GA', value: 'GA' },
            { label: 'HI', value: 'HI' },
            { label: 'ID', value: 'ID' },
            { label: 'IL', value: 'IL' },
            { label: 'IN', value: 'IN' },
            { label: 'IA', value: 'IA' },
            { label: 'KS', value: 'KS' },
            { label: 'KY', value: 'KY' },
            { label: 'LA', value: 'LA' },
            { label: 'ME', value: 'ME' },
            { label: 'MD', value: 'MD' },
            { label: 'MA', value: 'MA' },
            { label: 'MI', value: 'MI' },
            { label: 'MN', value: 'MN' },
            { label: 'MS', value: 'MS' },
            { label: 'MO', value: 'MO' },
            { label: 'MT', value: 'MT' },
            { label: 'NE', value: 'NE' },
            { label: 'NV', value: 'NV' },
            { label: 'NH', value: 'NH' },
            { label: 'NJ', value: 'NJ' },
            { label: 'NM', value: 'NM' },
            { label: 'NY', value: 'NY' },
            { label: 'NC', value: 'NC' },
            { label: 'ND', value: 'ND' },
            { label: 'OH', value: 'OH' },
            { label: 'OK', value: 'OK' },
            { label: 'OR', value: 'OR' },
            { label: 'PA', value: 'PA' },
            { label: 'RI', value: 'RI' },
            { label: 'SC', value: 'SC' },
            { label: 'SD', value: 'SD' },
            { label: 'TN', value: 'TN' },
            { label: 'TX', value: 'TX' },
            { label: 'UT', value: 'UT' },
            { label: 'VT', value: 'VT' },
            { label: 'VA', value: 'VA' },
            { label: 'WA', value: 'WA' },
            { label: 'WV', value: 'WV' },
            { label: 'WI', value: 'WI' },
            { label: 'WY', value: 'WY' },
            { label: 'AB', value: 'AB' },
            { label: 'BC', value: 'BC' },
            { label: 'MB', value: 'MB' },
            { label: 'NB', value: 'NB' },
            { label: 'NL', value: 'NL' },
            { label: 'NS', value: 'NS' },
            { label: 'NT', value: 'NT' },
            { label: 'NU', value: 'NU' },
            { label: 'ON', value: 'ON' },
            { label: 'PE', value: 'PE' },
            { label: 'QC', value: 'QC' },
            { label: 'SK', value: 'SK' },
            { label: 'YT', value: 'YT' },
            { label: 'Amazonas', value: 'Amazonas' },
            { label: 'Antioquia', value: 'Antioquia' },
            { label: 'Arauca', value: 'Arauca' },
            { label: 'Atlántico', value: 'Atlántico' },
            { label: 'Bogotá', value: 'Bogotá' },
            { label: 'Bolívar', value: 'Bolívar' },
            { label: 'Boyacá', value: 'Boyacá' },
            { label: 'Caldas', value: 'Caldas' },
            { label: 'Caquetá', value: 'Caquetá' },
            { label: 'Casanare', value: 'Casanare' },
            { label: 'Cauca', value: 'Cauca' },
            { label: 'Cesar', value: 'Cesar' },
            { label: 'Chocó', value: 'Chocó' },
            { label: 'Córdoba', value: 'Córdoba' },
            { label: 'Cundinamarca', value: 'Cundinamarca' },
            { label: 'Guainía', value: 'Guainía' },
            { label: 'Guaviare', value: 'Guaviare' },
            { label: 'Huila', value: 'Huila' },
            { label: 'La Guajira', value: 'La Guajira' },
            { label: 'Magdalena', value: 'Magdalena' },
            { label: 'Meta', value: 'Meta' },
            { label: 'Nariño', value: 'Nariño' },
            { label: 'Norte de Santander', value: 'Norte de Santander' },
            { label: 'Putumayo', value: 'Putumayo' },
            { label: 'Quindío', value: 'Quindío' },
            { label: 'Risaralda', value: 'Risaralda' },
            { label: 'San Andrés y Providencia', value: 'San Andrés y Providencia' },
            { label: 'Santander', value: 'Santander' },
            { label: 'Sucre', value: 'Sucre' },
            { label: 'Tolima', value: 'Tolima' },
            { label: 'Valle del Cauca', value: 'Valle del Cauca' },
            { label: 'Vaupés', value: 'Vaupés' },
            { label: 'Vichada', value: 'Vichada' }
        ];
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
        this.selectedLoadId = undefined;

        if (this.searchTimer) {
            window.clearTimeout(this.searchTimer);
        }

        this.searchTimer = window.setTimeout(() => {
            this.resetAndFetch(false);
        }, 400);
    }

    handleStateChange(event) {
        this.localStateCode = event.detail.value || '';
        this.selectedLoadId = undefined;

        this.dispatchEvent(
            new CustomEvent('statechange', {
                detail: { stateCode: this.localStateCode },
                bubbles: true,
                composed: true
            })
        );

        this.resetAndFetch(true);
    }

    handleRefresh() {
        this.resetAndFetch(true);
    }

    handleAutoRefreshToggle(event) {
        this.autoRefreshEnabled = event.target.checked;
        if (this.autoRefreshEnabled) {
            this.startAutoRefresh();
        } else {
            this.stopAutoRefresh();
        }
    }

    startAutoRefresh() {
        this.stopAutoRefresh();
        this.refreshInterval = window.setInterval(() => {
            this.resetAndFetch(true);
        }, 30000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            window.clearInterval(this.refreshInterval);
            this.refreshInterval = undefined;
        }
    }

    handleViewChange(event) {
        this.activeView = event.currentTarget.dataset.view || 'all';
        this.selectedLoadId = undefined;
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
                context: 'loadBoard',
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

            this.selectedLoadId = this.loads.length ? this.loads[0].Id : undefined;
            this.lastRefreshedAt = new Date().toLocaleTimeString();
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to load dispatch data.';
        } finally {
            if (requestId === this.requestSequence) {
                this.isLoading = false;
            }
        }
    }

    handleLoadSelect(event) {
        this.selectedLoadId = event.currentTarget.dataset.id;
    }

    handleOpenLoad() {
        if (!this.selectedLoad?.Id) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedLoad.Id,
                objectApiName: 'FreightTM__Load__c',
                actionName: 'view'
            }
        });
    }

    async handleEmailCarrier() {
    if (!this.selectedLoad?.Id) {
        return;
    }

    if (!this.selectedLoad?.carrierEmail) {
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
        loadId: this.selectedLoad.Id,
        loadName: this.selectedLoad.Name,
        carrierName: this.selectedLoad.carrierName,
        carrierEmail: this.selectedLoad.carrierEmail
    });

    if (result?.action === 'sent') {
        this.showToast(
            'RateCon Sent',
            `RateCon PDF was sent to ${this.selectedLoad.carrierEmail}.`,
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

async handlePingDriver() {
    if (!this.selectedLoad?.Id) {
        return;
    }

    const result = await PingDriverModal.open({
        size: 'small',
        description: 'Send the driver portal link by SMS.',
        loadId: this.selectedLoad.Id,
        loadName: this.selectedLoad.Name,
        driverId: this.selectedLoad.FreightTM__Driver__c,
        driverName: this.selectedLoad.driverName,
        driverPhone: this.selectedLoad.Driver_Phone_Number__c,
        driverCarrier: this.selectedLoad.Driver_Phone_Carrier__c,
        portalLink: this.selectedLoad.Driver_Portal_Link__c
    });

    if (result?.action === 'sent') {
        this.showToast(
            'Driver Ping Sent',
            `The portal link was queued for ${result.phoneNumber}.`,
            'success'
        );

        this.resetAndFetch(true);
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

showToast(title, message, variant) {
    this.dispatchEvent(
        new ShowToastEvent({
            title,
            message,
            variant
        })
    );
}

    async handleGenerateInvoice() {
    if (!this.selectedLoad?.Id) {
        return;
    }

    const result = await InvoicePreviewModal.open({
        size: 'large',
        description: 'Preview invoice PDF before saving it to load files.',
        loadId: this.selectedLoad.Id,
        loadName: this.selectedLoad.Name
    });

    if (result?.action === 'saved') {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invoice Saved',
                message: `Invoice PDF was saved to ${this.selectedLoad.Name} files.`,
                variant: 'success'
            })
        );

        this.resetAndFetch(true);
        return;
    }

    if (result?.action === 'error') {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invoice Error',
                message: result.message || 'Unable to save invoice PDF.',
                variant: 'error'
            })
        );
    }
}

    get activeLoadCount() {
        return this.summary?.totalLoads || 0;
    }

    get activeLoadLabel() {
        return this.localStateCode
            ? `Filtered by ${this.localStateCode}`
            : 'All active loads';
    }

    get exceptionCount() {
        return this.summary?.exceptionCount || 0;
    }

    get exceptionLabel() {
        return this.exceptionCount === 1
            ? 'Needs attention'
            : 'Need attention';
    }

    get onTimePercent() {
        return Number(this.summary?.onTimePercent || 0).toFixed(1);
    }

    get avgMargin() {
        return Number(this.summary?.avgMarginPercent || 0).toFixed(1);
    }

    get marginLabel() {
        return `${this.activeLoadCount} total loads`;
    }

    get invoiceReadyCount() {
        return this.summary?.invoiceReadyCount || 0;
    }

    get invoicePendingCount() {
        return Math.max(0, this.activeLoadCount - this.invoiceReadyCount);
    }

    get invoiceReadyLabel() {
        return `${this.invoiceReadyCount} Ready`;
    }

    get invoicePendingLabel() {
        return `${this.invoicePendingCount} Pending`;
    }

    get filteredLoadRows() {
        return this.loadRows;
    }

    matchesActiveView(load) {
        if (this.activeView === 'exceptions') {
            return load.isException;
        }

        if (this.activeView === 'invoiceReady') {
            return this.isInvoiceReady(load);
        }

        if (this.activeView === 'unassigned') {
            return load.carrierName === 'Unassigned' &&
                load.driverName === 'Unassigned' &&
                load.truckName === 'Unassigned';
        }

        if (this.activeView === 'lowMargin') {
            return load.marginPercent !== null && load.marginPercent < 15;
        }

        return true;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get pageNumber() {
        return Math.min(this.currentPage, this.totalPages);
    }

    get paginatedLoadRows() {
        return this.loadRows;
    }

    get pageRangeLabel() {
        if (!this.totalRecords) {
            return '0 loads';
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

    get hasLoads() {
        return this.loads.length > 0;
    }

    get selectedLoad() {
        if (this.selectedLoadId) {
            return this.loadRows.find((load) => load.Id === this.selectedLoadId);
        }

        return this.paginatedLoadRows.length ? this.paginatedLoadRows[0] : null;
    }

    get isEmailDisabled() {
        return !this.selectedLoad?.carrierEmail;
    }

    get loadRows() {
        return (this.loads || []).map((load) => {
            const pickupCity = load.FreightTM__Pickup_City__c || 'Origin';
            const deliveryCity = load.FreightTM__Delivery_City__c || 'Destination';

            const customerName =
                load.FreightTM__Customer__r?.Name ||
                load.FreightTM__Account__r?.Name ||
                load.Customer__r?.Name ||
                'Customer unavailable';

            const carrierName = load.FreightTM__Carrier_Obj__r?.Name || 'Unassigned';
            const carrierEmail =
                load.FreightTM__Carrier_Obj__r?.FreightTM__Email__c ||
                load.FreightTM__Carrier_Obj__r?.Email ||
                '';

            const driverName = load.FreightTM__Driver__r?.Name || 'Unassigned';
            const truckName = load.FreightTM__Truck__r?.Name || 'Unassigned';

            const status = load.FreightTM__Status__c || 'Open';
            const invoiceStatus = load.FreightTM__Invoice_Status__c || 'Unavailable';
            const billStatus = load.FreightTM__Bill_Status__c || 'Unavailable';

            const marginPercent = this.getMarginPercentValue(load);
            const margin = marginPercent === null ? '—' : `${marginPercent.toFixed(1)}%`;

            const isException = this.isExceptionLoad(load);
            const isSelected = load.Id === this.selectedLoadId;

            return {
                ...load,
                route: `${pickupCity} → ${deliveryCity}`,
                customerName,
                carrierName,
                carrierEmail,
                driverName,
                truckName,
                assignment: carrierName !== 'Unassigned'
                    ? carrierName
                    : driverName !== 'Unassigned'
                        ? driverName
                        : truckName !== 'Unassigned'
                            ? truckName
                            : 'Unassigned',
                status,
                invoiceStatus,
                billStatus,
                podLabel: load.POD_Received__c ? 'Yes' : 'No',
                exceptionReason: load.Exception_Reason__c,
                grossMargin: this.formatCurrency(load.FreightTM__Gross_Margin__c),
                margin,
                marginPercent,
                isException,
                pickupDateLabel: this.formatDate(load.FreightTM__Pickup_Date__c),
                deliveryDateLabel: this.formatDate(load.FreightTM__Delivery_Date__c),
                rowClass: `${isException ? 'load-row exception-row' : 'load-row'} ${isSelected ? 'selected-row' : ''}`,
                statusClass: isException
                    ? 'status-badge late'
                    : this.isCompletedLoad(load)
                        ? 'status-badge pod'
                        : status.toLowerCase().includes('pickup')
                            ? 'status-badge pickup'
                            : 'status-badge transit',
                marginClass: marginPercent !== null && marginPercent < 15
                    ? 'margin-cell warning'
                    : 'margin-cell'
            };
        });
    }

    isExceptionLoad(load) {
        const status = (load.FreightTM__Status__c || '').toLowerCase();

        return Boolean(load.Exception_Reason__c) ||
            status.includes('late') ||
            status.includes('exception') ||
            status.includes('delayed') ||
            status.includes('hold') ||
            status.includes('risk') ||
            status.includes('claim');
    }

    isCompletedLoad(load) {
        const status = (load.FreightTM__Status__c || '').toLowerCase();
        const billStatus = (load.FreightTM__Bill_Status__c || '').toLowerCase();

        return load.POD_Received__c === true ||
            status.includes('delivered') ||
            status.includes('complete') ||
            status.includes('pod') ||
            billStatus.includes('pod received');
    }

    isInvoiceReady(load) {
        const invoiceStatus = (load.FreightTM__Invoice_Status__c || '').toLowerCase();
        const billStatus = (load.FreightTM__Bill_Status__c || '').toLowerCase();

        return load.POD_Received__c === true &&
            (
                billStatus.includes('pod received') ||
                billStatus.includes('bill/pod received') ||
                invoiceStatus.includes('ready') ||
                invoiceStatus.includes('approved') ||
                invoiceStatus.includes('invoiced')
            );
    }

    getMarginPercentValue(load) {
        const rawValue = load.FreightTM__Gross_Margin_Percent__c;

        if (rawValue === null || rawValue === undefined || rawValue === '') {
            return null;
        }

        const numericValue = Number(rawValue);

        if (Number.isNaN(numericValue)) {
            return null;
        }

        return Math.abs(numericValue) <= 1 ? numericValue * 100 : numericValue;
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '$0.00';
        }

        const numericValue = Number(value);

        if (Number.isNaN(numericValue)) {
            return '$0.00';
        }

        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(numericValue);
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

    get allViewClass() {
        return this.activeView === 'all' ? 'view-pill active' : 'view-pill';
    }

    get exceptionViewClass() {
        return this.activeView === 'exceptions' ? 'view-pill active danger' : 'view-pill';
    }

    get invoiceViewClass() {
        return this.activeView === 'invoiceReady' ? 'view-pill active' : 'view-pill';
    }

    get unassignedViewClass() {
        return this.activeView === 'unassigned' ? 'view-pill active' : 'view-pill';
    }

    get lowMarginViewClass() {
        return this.activeView === 'lowMargin' ? 'view-pill active warning' : 'view-pill';
    }

    get lastRefreshedLabel() {
    return this.lastRefreshedAt
        ? `Last refreshed: ${this.lastRefreshedAt}`
        : 'Auto refresh not fired yet';
}
}