import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLoadPage from '@salesforce/apex/DispatchConsoleController.getLoadPage';

export default class DispatchMargin extends NavigationMixin(LightningElement) {
    @api stateCode;

    @track loads = [];
    @track summary = {};
    @track totalRecords = 0;
    @track activeView = 'all';
    @track searchKey = '';
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
        this.resetAndFetch(false);
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value || '';
        if (this.searchTimer) {
            window.clearTimeout(this.searchTimer);
        }
        this.searchTimer = window.setTimeout(() => this.resetAndFetch(false), 400);
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
                context: 'margin',
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
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load margin data.';
        } finally {
            if (requestId === this.requestSequence) {
                this.isLoading = false;
            }
        }
    }

    handleOpenLoad(event) {
        const loadId = event.currentTarget.dataset.id;

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

    get marginRows() {
        return (this.loads || []).map((load) => {
            const marginValue = this.getMarginPercentValue(load);

            const pickupCity = load.FreightTM__Pickup_City__c || 'Origin';
            const deliveryCity = load.FreightTM__Delivery_City__c || 'Destination';

            const pickupState = load.FreightTM__Pickup_State__c || '';
            const deliveryState = load.FreightTM__Delivery_State__c || '';

            const health = this.getMarginHealth(marginValue);

            return {
                Id: load.Id,
                Name: load.Name,
                route: `${pickupCity} → ${deliveryCity}`,
                routeStates: `${pickupState || '—'} → ${deliveryState || '—'}`,
                routeKey: `${pickupCity} → ${deliveryCity}`,
                carrierName: load.FreightTM__Carrier_Obj__r?.Name || 'Unassigned',
                grossMargin: this.formatCurrency(load.FreightTM__Gross_Margin__c),
                grossMarginValue: this.getCurrencyValue(load.FreightTM__Gross_Margin__c),
                marginValue,
                marginPercent: marginValue === null ? '—' : `${marginValue.toFixed(1)}%`,
                rowClass: marginValue !== null && marginValue < 15 ? 'margin-row low' : 'margin-row',
                marginClass: marginValue !== null && marginValue < 15 ? 'margin-percent warning' : 'margin-percent',
                healthLabel: health.label,
                healthType: health.type,
                healthClass: `health-pill ${health.type}`
            };
        });
    }

    get filteredMarginRows() {
        return this.marginRows;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get pageNumber() {
        return Math.min(this.currentPage, this.totalPages);
    }

    get paginatedMarginRows() {
        return this.marginRows;
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

    matchesActiveView(load) {
        if (this.activeView === 'lowMargin') {
            return load.marginValue !== null && load.marginValue < 15;
        }

        if (this.activeView === 'profitable') {
            return load.marginValue !== null && load.marginValue >= 25;
        }

        return true;
    }

    get hasMargins() {
        return this.loads.length > 0;
    }

    get totalGrossMargin() {
        return this.formatCurrency(this.summary?.totalGrossMargin || 0);
    }

    get avgMarginPercent() {
        return Number(this.summary?.avgMarginPercent || 0).toFixed(1);
    }

    get avgMarginLabel() {
        return `${this.summary?.totalLoads || 0} total loads`;
    }

    get lowMarginCount() {
        return this.summary?.lowMarginCount || 0;
    }

    get marginAtRisk() {
        return this.formatCurrency(this.summary?.marginAtRisk || 0);
    }

    get bestMarginRecord() {
        const rows = this.marginRows
            .filter((load) => load.marginValue !== null)
            .sort((a, b) => b.marginValue - a.marginValue);

        return rows.length ? rows[0] : null;
    }

    get bestMarginPercent() {
        const value = Number(this.summary?.bestMarginPercent || 0);
        return this.summary?.bestMarginLoad ? `${value.toFixed(1)}%` : '—';
    }

    get bestMarginLoad() {
        return this.summary?.bestMarginLoad || 'No margin data';
    }

    get marginCountLabel() {
        return `${this.summary?.totalLoads || 0} margin records`;
    }

    get filteredCountLabel() {
        return `${this.totalRecords} records found`;
    }

    get distributionRows() {
        const rows = [
            { label: 'Excellent · 30%+', type: 'excellent', count: this.summary?.excellentMarginCount || 0 },
            { label: 'Healthy · 20–29%', type: 'healthy', count: this.summary?.healthyMarginCount || 0 },
            { label: 'Watch · 15–19%', type: 'watch', count: this.summary?.watchMarginCount || 0 },
            { label: 'Low · Under 15%', type: 'low', count: this.summary?.lowMarginCount || 0 }
        ];
        const max = Math.max(...rows.map((row) => row.count), 1);
        return rows.map((row) => ({
            ...row,
            style: `--bar-width: ${(row.count / max) * 100}%;`,
            barClass: `bar-fill ${row.type}`
        }));
    }

    get laneRows() {
        const lanes = {};

        this.marginRows.forEach((load) => {
            if (!lanes[load.routeKey]) {
                lanes[load.routeKey] = {
                    key: load.routeKey,
                    route: load.routeKey,
                    loadCount: 0,
                    totalMargin: 0,
                    marginRecords: 0
                };
            }

            lanes[load.routeKey].loadCount += 1;

            if (load.marginValue !== null) {
                lanes[load.routeKey].totalMargin += load.marginValue;
                lanes[load.routeKey].marginRecords += 1;
            }
        });

        return Object.values(lanes)
            .filter((lane) => lane.marginRecords > 0)
            .map((lane) => ({
                ...lane,
                avgMarginValue: lane.totalMargin / lane.marginRecords,
                avgMargin: (lane.totalMargin / lane.marginRecords).toFixed(1)
            }));
    }

    get topLaneRows() {
        return [...this.laneRows]
            .sort((a, b) => b.avgMarginValue - a.avgMarginValue)
            .slice(0, 5);
    }

    get worstLaneRows() {
        return [...this.laneRows]
            .sort((a, b) => a.avgMarginValue - b.avgMarginValue)
            .slice(0, 5);
    }

    get allViewClass() {
        return this.activeView === 'all' ? 'view-pill active' : 'view-pill';
    }

    get lowMarginViewClass() {
        return this.activeView === 'lowMargin' ? 'view-pill active warning' : 'view-pill';
    }

    get profitableViewClass() {
        return this.activeView === 'profitable' ? 'view-pill active success' : 'view-pill';
    }

    getMarginHealth(value) {
        if (value === null) {
            return {
                type: 'unknown',
                label: 'No Data'
            };
        }

        if (value < 15) {
            return {
                type: 'low',
                label: 'Low Margin'
            };
        }

        if (value < 20) {
            return {
                type: 'watch',
                label: 'Watch'
            };
        }

        if (value < 30) {
            return {
                type: 'healthy',
                label: 'Healthy'
            };
        }

        return {
            type: 'excellent',
            label: 'Excellent'
        };
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

    getCurrencyValue(value) {
        if (value === null || value === undefined || value === '') {
            return 0;
        }

        const numericValue = Number(value);

        if (Number.isNaN(numericValue)) {
            return 0;
        }

        return numericValue;
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        const numericValue = Number(value);

        if (Number.isNaN(numericValue)) {
            return '—';
        }

        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(numericValue);
    }
}