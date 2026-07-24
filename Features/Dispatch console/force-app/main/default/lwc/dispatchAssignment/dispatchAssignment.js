import { LightningElement, api, track } from 'lwc';
import assignToLoads from '@salesforce/apex/DispatchConsoleController.assignToLoads';
import getLoadPage from '@salesforce/apex/DispatchConsoleController.getLoadPage';
import getResourcePage from '@salesforce/apex/DispatchConsoleController.getResourcePage';

export default class DispatchAssignment extends LightningElement {
    @api stateCode;

    @track trucks = [];
    @track drivers = [];
    @track carriers = [];
    @track loads = [];
    @track localStateCode = '';
    @track selectedType = 'Truck';
    @track selectedRecordId;
    @track selectedRecordName;
    @track selectedLoadIds = [];
    @track isAssigning = false;
    @track isResourceLoading = false;
    @track isLoadLoading = false;
    @track errorMessage;

    @track loadSearchKey = '';
    @track loadStatusFilter = 'All';
    @track activeLoadView = 'all';
    @track availableStatuses = [];

    @track resourcePage = 1;
    @track loadPage = 1;
    @track resourceTotalRecords = 0;
    @track loadTotalRecords = 0;
    @track resourceCounts = { truck: 0, driver: 0, carrier: 0 };

    pageSize = 10;
    loadSearchTimer;
    resourceRequestSequence = 0;
    loadRequestSequence = 0;

    truckColumns = [
        { label: 'Truck', fieldName: 'Name', type: 'text' },
        { label: 'State', fieldName: 'State_Province__c', type: 'text' },
        { label: 'Status', fieldName: 'FreightTM__Status__c', type: 'text' },
        { label: 'Driver', fieldName: 'driverName', type: 'text' },
        { label: 'Type', fieldName: 'FreightTM__Type__c', type: 'text' },
        { label: 'Plate', fieldName: 'FreightTM__License_Plate__c', type: 'text' }
    ];

    driverColumns = [
        { label: 'Driver', fieldName: 'displayName', type: 'text' },
        { label: 'State', fieldName: 'FreightTM__State__c', type: 'text' },
        { label: 'City', fieldName: 'FreightTM__City__c', type: 'text' },
        { label: 'Phone', fieldName: 'FreightTM__Phone__c', type: 'phone' },
        { label: 'Type', fieldName: 'FreightTM__Type__c', type: 'text' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' }
    ];

    carrierColumns = [
        { label: 'Carrier', fieldName: 'Name', type: 'text' },
        { label: 'State', fieldName: 'carrierState', type: 'text' },
        { label: 'Billing City', fieldName: 'FreightTM__Billing_City__c', type: 'text' },
        { label: 'Phone', fieldName: 'FreightTM__Phone__c', type: 'phone' },
        { label: 'Primary Contact', fieldName: 'FreightTM__Primary_Contact__c', type: 'text' },
        { label: 'Onboarding', fieldName: 'FreightTM__On_boarding_Status__c', type: 'text' }
    ];

    loadColumns = [
        { label: 'Load', fieldName: 'Name', type: 'text' },
        { label: 'Matched Point', fieldName: 'matchedPoint', type: 'text' },
        { label: 'Route', fieldName: 'route', type: 'text' },
        { label: 'Status', fieldName: 'FreightTM__Status__c', type: 'text' },
        { label: 'Carrier', fieldName: 'carrierName', type: 'text' },
        { label: 'Driver', fieldName: 'driverName', type: 'text' },
        { label: 'Truck', fieldName: 'truckName', type: 'text' },
        { label: 'Pickup Date', fieldName: 'FreightTM__Pickup_Date__c', type: 'date' },
        { label: 'Delivery Date', fieldName: 'FreightTM__Delivery_Date__c', type: 'date' }
    ];

    connectedCallback() {
        this.localStateCode = this.stateCode || '';
        this.fetchResourcePage('first', true);
        this.fetchLoadPage('first', true);
    }

    renderedCallback() {
        const incomingState = this.stateCode || '';
        if (incomingState !== this.localStateCode) {
            this.localStateCode = incomingState;
            this.loadSelectedState(false);
        }
    }

    disconnectedCallback() {
        if (this.loadSearchTimer) {
            window.clearTimeout(this.loadSearchTimer);
        }
    }

    get stateOptions() {
        const values = [
            'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL',
            'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME',
            'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH',
            'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI',
            'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI',
            'WY',
            'AB', 'BC', 'MB', 'NB', 'NL', 'NS', 'NT', 'NU', 'ON', 'PE',
            'QC', 'SK', 'YT',
            'Amazonas', 'Antioquia', 'Arauca', 'Atlántico', 'Bogotá',
            'Bolívar', 'Boyacá', 'Caldas', 'Caquetá', 'Casanare', 'Cauca',
            'Cesar', 'Chocó', 'Córdoba', 'Cundinamarca', 'Guainía',
            'Guaviare', 'Huila', 'La Guajira', 'Magdalena', 'Meta',
            'Nariño', 'Norte de Santander', 'Putumayo', 'Quindío',
            'Risaralda', 'San Andrés y Providencia', 'Santander', 'Sucre',
            'Tolima', 'Valle del Cauca', 'Vaupés', 'Vichada'
        ];

        return [
            { label: 'Select a State', value: '' },
            ...values.map((value) => ({
                label: value,
                value
            }))
        ];
    }

    get loadStatusOptions() {
        return [
            { label: 'All', value: 'All' },
            ...(this.availableStatuses || []).map((status) => ({
                label: status,
                value: status
            }))
        ];
    }

    handleStateChange(event) {
        this.localStateCode = event.detail.value || '';
        this.loadSelectedState(true);
    }

    handleStateSearch() {
        this.loadSelectedState(true);
    }

    loadSelectedState(dispatchStateEvent = true) {
        this.selectedRecordId = undefined;
        this.selectedRecordName = undefined;
        this.selectedLoadIds = [];
        this.loadSearchKey = '';
        this.loadStatusFilter = 'All';
        this.activeLoadView = 'all';
        this.resourcePage = 1;
        this.loadPage = 1;

        if (dispatchStateEvent) {
            this.dispatchEvent(
                new CustomEvent('statechange', {
                    detail: { stateCode: this.localStateCode },
                    bubbles: true,
                    composed: true
                })
            );
        }

        this.fetchResourcePage('first', true);
        this.fetchLoadPage('first', true);
    }

    handleResourceTab(event) {
        this.selectedType = event.currentTarget.dataset.type;
        this.selectedRecordId = undefined;
        this.selectedRecordName = undefined;
        this.resourcePage = 1;
        this.fetchResourcePage('first', true);
    }

    handleResourceRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        if (!selectedRows || selectedRows.length === 0) {
            this.selectedRecordId = undefined;
            this.selectedRecordName = undefined;
            return;
        }
        const selectedRow = selectedRows[0];
        this.selectedRecordId = selectedRow.Id;
        this.selectedRecordName = selectedRow.Name || selectedRow.displayName;
    }

    handleLoadSearch(event) {
        this.loadSearchKey = event.target.value || '';
        if (this.loadSearchTimer) {
            window.clearTimeout(this.loadSearchTimer);
        }
        this.loadSearchTimer = window.setTimeout(() => {
            this.loadPage = 1;
            this.fetchLoadPage('first', false);
        }, 400);
    }

    handleLoadStatusChange(event) {
        this.loadStatusFilter = event.detail.value || 'All';
        this.loadPage = 1;
        this.fetchLoadPage('first', false);
    }

    handleLoadViewChange(event) {
        this.activeLoadView = event.currentTarget.dataset.view || 'all';
        this.selectedLoadIds = [];
        this.loadPage = 1;
        this.fetchLoadPage('first', false);
    }

    handleLoadRowSelection(event) {
        const pageIds = new Set(this.loadRows.map((row) => row.Id));
        const selectedPageIds = event.detail.selectedRows.map((row) => row.Id);
        const preservedIds = this.selectedLoadIds.filter((id) => !pageIds.has(id));
        this.selectedLoadIds = [...preservedIds, ...selectedPageIds];
    }

    handleSelectAllLoads() {
        const currentIds = this.loadRows.map((load) => load.Id);
        this.selectedLoadIds = [...new Set([...this.selectedLoadIds, ...currentIds])];
    }

    handleDeselectLoads() {
        this.selectedLoadIds = [];
    }

    handleClearLoadFilters() {
        this.loadSearchKey = '';
        this.loadStatusFilter = 'All';
        this.activeLoadView = 'all';
        this.selectedLoadIds = [];
        this.loadPage = 1;
        this.fetchLoadPage('first', false);
    }

    handleResourceFirstPage() {
        this.fetchResourcePage('first', true);
    }

    handleResourcePreviousPage() {
        this.fetchResourcePage('previous', false);
    }

    handleResourceNextPage() {
        this.fetchResourcePage('next', false);
    }

    handleResourceLastPage() {
        this.fetchResourcePage('last', false);
    }

    handleLoadFirstPage() {
        this.fetchLoadPage('first', false);
    }

    handleLoadPreviousPage() {
        this.fetchLoadPage('previous', false);
    }

    handleLoadNextPage() {
        this.fetchLoadPage('next', false);
    }

    handleLoadLastPage() {
        this.fetchLoadPage('last', false);
    }

    async fetchResourcePage(direction = 'first', includeCounts = false) {
        const rows = this.currentResourceRows;
        const firstRecord = rows.length ? rows[0] : null;
        const lastRecord = rows.length ? rows[rows.length - 1] : null;
        const cursorRecord = direction === 'previous' ? firstRecord : lastRecord;
        const requestId = ++this.resourceRequestSequence;
        this.isResourceLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getResourcePage({
                resourceType: this.selectedType,
                stateCode: this.localStateCode || '',
                searchKey: '',
                pageSize: this.pageSize,
                cursorCreatedDate: cursorRecord?.CreatedDate || null,
                cursorId: cursorRecord?.Id || null,
                direction,
                includeCounts
            });
            if (requestId !== this.resourceRequestSequence) {
                return;
            }
            this.trucks = result?.trucks || [];
            this.drivers = result?.drivers || [];
            this.carriers = result?.carriers || [];
            this.resourceTotalRecords = result?.totalCount || 0;
            this.selectedRecordId = undefined;
            this.selectedRecordName = undefined;
            if (includeCounts) {
                this.resourceCounts = {
                    truck: result?.truckCount || 0,
                    driver: result?.driverCount || 0,
                    carrier: result?.carrierCount || 0
                };
            }
            if (direction === 'next') {
                this.resourcePage = Math.min(this.resourceTotalPages, this.resourcePage + 1);
            } else if (direction === 'previous') {
                this.resourcePage = Math.max(1, this.resourcePage - 1);
            } else if (direction === 'last') {
                this.resourcePage = this.resourceTotalPages;
            } else {
                this.resourcePage = 1;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load resources.';
        } finally {
            if (requestId === this.resourceRequestSequence) {
                this.isResourceLoading = false;
            }
        }
    }

    async fetchLoadPage(direction = 'first', includeSummary = false) {
        const firstRecord = this.loads.length ? this.loads[0] : null;
        const lastRecord = this.loads.length ? this.loads[this.loads.length - 1] : null;
        const cursorRecord = direction === 'previous' ? firstRecord : lastRecord;
        const requestId = ++this.loadRequestSequence;
        this.isLoadLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getLoadPage({
                context: 'assignment',
                stateCode: this.localStateCode || '',
                searchKey: this.loadSearchKey || '',
                viewName: this.activeLoadView || 'all',
                statusFilter: this.loadStatusFilter || 'All',
                pageSize: this.pageSize,
                cursorCreatedDate: cursorRecord?.CreatedDate || null,
                cursorId: cursorRecord?.Id || null,
                direction,
                includeSummary
            });
            if (requestId !== this.loadRequestSequence) {
                return;
            }
            this.loads = result?.records || [];
            this.loadTotalRecords = result?.totalCount || 0;
            if (includeSummary) {
                this.availableStatuses = result?.statuses || [];
            }
            if (direction === 'next') {
                this.loadPage = Math.min(this.loadTotalPages, this.loadPage + 1);
            } else if (direction === 'previous') {
                this.loadPage = Math.max(1, this.loadPage - 1);
            } else if (direction === 'last') {
                this.loadPage = this.loadTotalPages;
            } else {
                this.loadPage = 1;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load assignment loads.';
        } finally {
            if (requestId === this.loadRequestSequence) {
                this.isLoadLoading = false;
            }
        }
    }

    handlePreviewAssignment() {
        if (!this.selectedRecordId) {
            alert('Select one truck, driver, or carrier first.');
            return;
        }

        if (!this.selectedLoadIds.length) {
            alert('Select at least one load to preview the assignment.');
            return;
        }

        alert(`${this.selectedType} ${this.selectedRecordName} will be assigned to ${this.selectedLoadIds.length} load(s).`);
    }

    async handleAssign() {
        if (!this.selectedRecordId) {
            alert('Please select a truck, driver, or carrier.');
            return;
        }

        if (!this.selectedLoadIds.length) {
            alert('Please select at least one load.');
            return;
        }

        this.isAssigning = true;

        try {
            await assignToLoads({
                loadIds: this.selectedLoadIds,
                selectedRecordId: this.selectedRecordId,
                selectedType: this.selectedType
            });

            this.selectedLoadIds = [];

            this.loadPage = 1;
            this.fetchLoadPage('first', true);
            this.fetchResourcePage('first', true);
        } catch (error) {
            alert(error?.body?.message || error?.message || 'Unable to assign loads.');
        } finally {
            this.isAssigning = false;
        }
    }

    get truckRows() {
        return (this.trucks || []).map((truck) => ({
            ...truck,
            driverName: truck.FreightTM__Driver__r?.Name || 'Unassigned'
        }));
    }

    get driverRows() {
        return (this.drivers || []).map((driver) => ({
            ...driver,
            displayName: `${driver.FreightTM__First_Name__c || ''} ${driver.Name || ''}`.trim() || driver.Name
        }));
    }

    get carrierRows() {
        return (this.carriers || []).map((carrier) => ({
            ...carrier,
            carrierState:
                carrier.FreightTM__State_Province__c ||
                carrier.FreightTM__Billing_State_Province__c ||
                ''
        }));
    }

    get loadRows() {
        return (this.loads || []).map((load) => {
            const pickupCity = load.FreightTM__Pickup_City__c || 'Origin';
            const deliveryCity = load.FreightTM__Delivery_City__c || 'Destination';

            const carrierName = load.FreightTM__Carrier_Obj__r?.Name || 'Unassigned';
            const driverName = load.FreightTM__Driver__r?.Name || 'Unassigned';
            const truckName = load.FreightTM__Truck__r?.Name || 'Unassigned';

            return {
                ...load,
                route: `${pickupCity} → ${deliveryCity}`,
                matchedPoint: this.getMatchedPointLabel(load),
                carrierName,
                driverName,
                truckName,
                isUnassigned:
                    carrierName === 'Unassigned' &&
                    driverName === 'Unassigned' &&
                    truckName === 'Unassigned',
                isException: this.isExceptionLoad(load),
                isReady:
                    load.POD_Received__c === true ||
                    String(load.FreightTM__Bill_Status__c || '').toLowerCase().includes('pod received')
            };
        });
    }

    get filteredLoadRows() {
        return this.loadRows;
    }

    matchesLoadView(load) {
        if (this.activeLoadView === 'unassigned') {
            return load.isUnassigned;
        }

        if (this.activeLoadView === 'exceptions') {
            return load.isException;
        }

        if (this.activeLoadView === 'ready') {
            return load.isReady;
        }

        return true;
    }

    get currentResourceRows() {
        if (this.selectedType === 'Truck') {
            return this.truckRows;
        }

        if (this.selectedType === 'Driver') {
            return this.driverRows;
        }

        return this.carrierRows;
    }

    get resourceTotalPages() {
        return Math.max(1, Math.ceil(this.resourceTotalRecords / this.pageSize));
    }

    get resourcePageNumber() {
        return Math.min(this.resourcePage, this.resourceTotalPages);
    }

    get paginatedTruckRows() {
        return this.truckRows;
    }

    get paginatedDriverRows() {
        return this.driverRows;
    }

    get paginatedCarrierRows() {
        return this.carrierRows;
    }

    get resourceRangeLabel() {
        if (!this.resourceTotalRecords) {
            return '0 records';
        }
        const start = ((this.resourcePageNumber - 1) * this.pageSize) + 1;
        const end = Math.min(start + this.currentResourceRows.length - 1, this.resourceTotalRecords);
        return `Showing ${start}-${end} of ${this.resourceTotalRecords}`;
    }

    get resourcePreviousDisabled() {
        return this.isResourceLoading || this.resourcePageNumber <= 1;
    }

    get resourceNextDisabled() {
        return this.isResourceLoading || this.resourcePageNumber >= this.resourceTotalPages;
    }

    get loadTotalPages() {
        return Math.max(1, Math.ceil(this.loadTotalRecords / this.pageSize));
    }

    get loadPageNumber() {
        return Math.min(this.loadPage, this.loadTotalPages);
    }

    get paginatedLoadRows() {
        return this.loadRows;
    }

    get loadRangeLabel() {
        if (!this.loadTotalRecords) {
            return '0 loads';
        }
        const start = ((this.loadPageNumber - 1) * this.pageSize) + 1;
        const end = Math.min(start + this.loads.length - 1, this.loadTotalRecords);
        return `Showing ${start}-${end} of ${this.loadTotalRecords}`;
    }

    get loadPreviousDisabled() {
        return this.isLoadLoading || this.loadPageNumber <= 1;
    }

    get loadNextDisabled() {
        return this.isLoadLoading || this.loadPageNumber >= this.loadTotalPages;
    }

    get selectedResourceRows() {
        return this.selectedRecordId ? [this.selectedRecordId] : [];
    }

    get selectedLoadRows() {
        return this.loadRows.filter((load) => this.selectedLoadIds.includes(load.Id));
    }

    get selectedLoadCount() {
        return this.selectedLoadIds.length;
    }

    get selectedResourceRecord() {
        if (!this.selectedRecordId) {
            return null;
        }

        if (this.selectedType === 'Truck') {
            return this.truckRows.find((record) => record.Id === this.selectedRecordId);
        }

        if (this.selectedType === 'Driver') {
            return this.driverRows.find((record) => record.Id === this.selectedRecordId);
        }

        return this.carrierRows.find((record) => record.Id === this.selectedRecordId);
    }

    get matchedStates() {
        return this.localStateCode ? [this.localStateCode] : [];
    }

    get truckCount() {
        return this.resourceCounts?.truck || 0;
    }

    get driverCount() {
        return this.resourceCounts?.driver || 0;
    }

    get carrierCount() {
        return this.resourceCounts?.carrier || 0;
    }

    get loadCount() {
        return this.loadTotalRecords || 0;
    }

    get isTruckTab() {
        return this.selectedType === 'Truck';
    }

    get isDriverTab() {
        return this.selectedType === 'Driver';
    }

    get isCarrierTab() {
        return this.selectedType === 'Carrier';
    }

    get hasResources() {
        if (this.selectedType === 'Truck') {
            return this.truckRows.length > 0;
        }

        if (this.selectedType === 'Driver') {
            return this.driverRows.length > 0;
        }

        return this.carrierRows.length > 0;
    }

    get hasLoads() {
        return this.loads.length > 0;
    }

    get assignDisabled() {
        return this.isAssigning || !this.selectedRecordId || this.selectedLoadIds.length === 0;
    }

    get assignButtonLabel() {
        if (!this.selectedRecordName) {
            return 'Select a resource';
        }

        if (!this.selectedLoadIds.length) {
            return 'Select loads';
        }

        return `Assign ${this.selectedType}`;
    }

    get previewText() {
        if (!this.selectedRecordName) {
            return 'Choose one truck, driver, or carrier from the table above.';
        }

        if (!this.selectedLoadIds.length) {
            return `${this.selectedRecordName} selected. Now choose one or more loads.`;
        }

        return `${this.selectedRecordName} → ${this.selectedLoadIds.length} selected load(s).`;
    }

    get assignmentStateLabel() {
        return this.localStateCode ? this.localStateCode : 'No State';
    }

    get assignmentStateClass() {
        return this.localStateCode ? 'state-chip active' : 'state-chip';
    }

    get truckTabClass() {
        return this.selectedType === 'Truck' ? 'resource-tab active' : 'resource-tab';
    }

    get driverTabClass() {
        return this.selectedType === 'Driver' ? 'resource-tab active' : 'resource-tab';
    }

    get carrierTabClass() {
        return this.selectedType === 'Carrier' ? 'resource-tab active' : 'resource-tab';
    }

    get allLoadsViewClass() {
        return this.activeLoadView === 'all' ? 'view-pill active' : 'view-pill';
    }

    get unassignedViewClass() {
        return this.activeLoadView === 'unassigned' ? 'view-pill active' : 'view-pill';
    }

    get exceptionsViewClass() {
        return this.activeLoadView === 'exceptions' ? 'view-pill active danger' : 'view-pill';
    }

    get readyViewClass() {
        return this.activeLoadView === 'ready' ? 'view-pill active success' : 'view-pill';
    }

    getMatchedPointLabel(load) {
        const selectedState = this.localStateCode;

        if (!selectedState) {
            return 'All States';
        }

        if ((load.FreightTM__Pickup_State__c || '') === selectedState) {
            return `Pickup · ${load.FreightTM__Pickup_City__c || selectedState}`;
        }

        if ((load.FreightTM__Delivery_State__c || '') === selectedState) {
            return `Delivery · ${load.FreightTM__Delivery_City__c || selectedState}`;
        }

        return 'Not matched';
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
}