import { LightningElement, api, track } from 'lwc';

import login from '@salesforce/apex/CustomerPortalController.login';
import logout from '@salesforce/apex/CustomerPortalController.logout';
import getPortalData from '@salesforce/apex/CustomerPortalController.getPortalData';
import submitCustomerAction from '@salesforce/apex/CustomerPortalController.submitCustomerAction';
import uploadPod from '@salesforce/apex/CustomerPortalController.uploadPod';
import recordPortalOpened from '@salesforce/apex/CustomerPortalController.recordPortalOpened';
import recordDocumentViewed from '@salesforce/apex/CustomerPortalController.recordDocumentViewed';
import getDocumentDownloadUrl from '@salesforce/apex/CustomerPortalController.getDocumentDownloadUrl';
import updateLoadStatus from '@salesforce/apex/CustomerPortalController.updateLoadStatus';

const SESSION_KEY = 'ftmCustomerPortalSessionKey';
const PAGE_SIZE = 10;

export default class CustomerPortal extends LightningElement {
    @api pageName = 'dashboard';
    @api loadId;

    loadDetailSource = 'dashboard';

    @track data;
    @track error;
    @track actionMessage;
    @track loginError;

    sessionKey;
    username = '';
    password = '';
    loading = true;
    contentLoading = false;
    loginInProgress = false;
    actionInProgress = false;
    portalOpenedRecorded = false;
    activeAction = null;
    activeLoadId = null;
    activeLoadNumber = null;
    messageValue = '';
    selectedFile;
    selectedFileBase64;

    searchDraft = '';
    searchTerm = '';
    statusFilter = 'all';
    pendingStatuses = {};
    savingLoadId = null;

    dashboardPage = 1;
    currentPage = 1;
    futurePage = 1;
    deliveredPage = 1;
    documentsPage = 1;
    invoicesPage = 1;

    pageCache = new Map();
    popStateHandler;

    connectedCallback() {
        this.readRoute();
        this.sessionKey = window.localStorage.getItem(SESSION_KEY);
        this.popStateHandler = () => {
            this.readRoute();
            this.resetViewState();
            this.loadPortal({ preserveLayout: true, useCache: true });
        };
        window.addEventListener('popstate', this.popStateHandler);

        if (!this.sessionKey) {
            this.loading = false;
            return;
        }
        this.loadPortal({ preserveLayout: false, useCache: true });
    }

    disconnectedCallback() {
        if (this.popStateHandler) window.removeEventListener('popstate', this.popStateHandler);
    }

    readRoute() {
        const params = new URLSearchParams(window.location.search);
        this.loadId = params.get('loadId') || params.get('id') || null;
        this.pageName = params.get('p') || this.pageName || 'dashboard';
        this.loadDetailSource = this.pageName === 'load' && params.get('from') === 'shipments' ? 'shipments' : 'dashboard';
    }

    get showLogin() { return !this.loading && !this.sessionKey && !this.hasData; }
    get hasData() { return !this.loading && !this.error && !!this.data; }
    get context() { return this.data?.context || {}; }
    get summary() { return this.data?.summary || {}; }
    get shipments() { return this.data?.shipments || []; }
    get documents() { return this.data?.documents || []; }
    get invoices() { return this.data?.invoices || []; }
    get selectedLoad() { return this.data?.selectedLoad || this.shipments[0]; }

    get isDashboard() { return this.pageName === 'dashboard'; }
    get isShipmentsPage() { return this.pageName === 'shipments'; }
    get isTrackingPage() { return this.pageName === 'tracking'; }
    get isLoadPage() { return this.pageName === 'load'; }
    get isCurrentShipmentDetail() { return this.isLoadPage && this.loadDetailSource === 'shipments'; }
    get isDashboardLoadDetail() { return this.isLoadPage && !this.isCurrentShipmentDetail; }
    get isDocumentsPage() { return this.pageName === 'documents'; }
    get isInvoicesPage() { return this.pageName === 'invoices'; }

    get filteredShipments() {
        return this.shipments.filter((shipment) => this.matchesSearch(shipment) && this.matchesStatusFilter(shipment));
    }
    get currentShipments() { return this.filteredShipments.filter((shipment) => shipment.bucket === 'current'); }
    get futureShipments() { return this.filteredShipments.filter((shipment) => shipment.bucket === 'future'); }
    get deliveredShipments() { return this.filteredShipments.filter((shipment) => shipment.bucket === 'delivered'); }
    get trackingShipments() { return this.shipments.filter((shipment) => shipment.hasTrackingMap); }

    get filteredDocuments() {
        const term = this.normalizedSearch;
        if (!term) return this.documents;
        return this.documents.filter((doc) => `${doc.title || ''} ${doc.type || ''} ${doc.loadNumber || ''}`.toLowerCase().includes(term));
    }
    get filteredInvoices() {
        const term = this.normalizedSearch;
        if (!term) return this.invoices;
        return this.invoices.filter((invoice) => {
            const pickup = invoice.parentLoad?.pickupLabel || '';
            const delivery = invoice.parentLoad?.deliveryLabel || '';
            return `${invoice.invoiceNumber || ''} ${invoice.loadNumber || ''} ${invoice.status || ''} ${pickup} ${delivery}`
                .toLowerCase()
                .includes(term);
        });
    }

    get pagedDashboardShipments() { return this.paginate(this.filteredShipments, this.dashboardPage); }
    get pagedCurrentShipments() { return this.paginate(this.currentShipments, this.currentPage); }
    get pagedFutureShipments() { return this.paginate(this.futureShipments, this.futurePage); }
    get pagedDeliveredShipments() { return this.paginate(this.deliveredShipments, this.deliveredPage); }
    get pagedDocuments() { return this.paginate(this.filteredDocuments, this.documentsPage); }
    get pagedInvoices() { return this.paginate(this.filteredInvoices, this.invoicesPage); }

    get hasShipments() { return this.filteredShipments.length > 0; }
    get hasCurrentShipments() { return this.currentShipments.length > 0; }
    get hasFutureShipments() { return this.futureShipments.length > 0; }
    get hasDeliveredShipments() { return this.deliveredShipments.length > 0; }
    get hasTrackingShipments() { return this.trackingShipments.length > 0; }
    get hasDocuments() { return this.filteredDocuments.length > 0; }
    get hasInvoices() { return this.filteredInvoices.length > 0; }
    get hasSelectedLoad() { return !!this.selectedLoad; }
    get hasSelectedTrackingMap() { return !!(this.selectedLoad && this.selectedLoad.hasTrackingMap); }
    get hasSelectedRouteMap() { return !!(this.selectedLoad && this.selectedLoad.pickupMapAddress && this.selectedLoad.deliveryMapAddress); }

    get currentShipmentCount() { return this.currentShipments.length; }
    get futureShipmentCount() { return this.futureShipments.length; }
    get deliveredShipmentCount() { return this.deliveredShipments.length; }
    get trackingShipmentCount() { return this.trackingShipments.length; }
    get documentCount() { return this.summary.documentCount ?? this.documents.length; }
    get invoiceCount() { return this.summary.invoiceCount ?? this.invoices.length; }
    get openInvoiceCount() {
        const openStatuses = new Set(['ready to invoice', 'invoiced', 'overdue']);
        return this.invoices.filter((invoice) => openStatuses.has((invoice.status || '').trim().toLowerCase())).length;
    }

    get normalizedSearch() { return (this.searchTerm || '').trim().toLowerCase(); }
    get formattedOnTimeRate() {
        const value = this.summary.onTimeRate;
        return value === null || value === undefined ? '—' : `${value}%`;
    }

    get statusOptions() {
        return [
            { label: '--None--', value: '__NONE__' },
            { label: 'Assigned', value: 'Assigned' },
            { label: 'Dispatched', value: 'Dispatched' },
            { label: 'In Transit to Pickup', value: 'In Transit to Pickup' },
            { label: 'At Shipping', value: 'At Shipping' },
            { label: 'In Transit to Delivery', value: 'In Transit to Delivery' },
            { label: 'At Receiving', value: 'At Receiving' },
            { label: 'Delivered', value: 'Delivered' }
        ];
    }
    get filterOptions() {
        return [
            { label: 'All loads', value: 'all' },
            { label: 'Active', value: 'active' },
            { label: 'In transit', value: 'transit' },
            { label: 'Delivered', value: 'delivered' },
            { label: 'Delayed', value: 'delayed' }
        ];
    }

    get dashboardUrl() { return '?p=dashboard'; }
    get shipmentsUrl() { return '?p=shipments'; }
    get trackingUrl() { return '?p=tracking'; }
    get documentsUrl() { return '?p=documents'; }
    get invoicesUrl() { return '?p=invoices'; }
    get dashboardNavClass() { return this.navClass('dashboard'); }
    get shipmentsNavClass() { return this.navClass('shipments'); }
    get trackingNavClass() { return this.navClass('tracking'); }
    get documentsNavClass() { return this.navClass('documents'); }
    get invoicesNavClass() { return this.navClass('invoices'); }
    navClass(page) { return this.pageName === page ? 'nav-pill active' : 'nav-pill'; }

    get dashboardPagination() { return this.paginationInfo(this.filteredShipments.length, this.dashboardPage); }
    get currentPagination() { return this.paginationInfo(this.currentShipments.length, this.currentPage); }
    get futurePagination() { return this.paginationInfo(this.futureShipments.length, this.futurePage); }
    get deliveredPagination() { return this.paginationInfo(this.deliveredShipments.length, this.deliveredPage); }
    get documentPagination() { return this.paginationInfo(this.filteredDocuments.length, this.documentsPage); }
    get invoicePagination() { return this.paginationInfo(this.filteredInvoices.length, this.invoicesPage); }

    paginate(items, page) {
        const start = (page - 1) * PAGE_SIZE;
        return items.slice(start, start + PAGE_SIZE);
    }
    paginationInfo(total, page) {
        const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
        const safePage = Math.min(page, totalPages);
        const start = total === 0 ? 0 : ((safePage - 1) * PAGE_SIZE) + 1;
        const end = Math.min(safePage * PAGE_SIZE, total);
        return {
            show: total > PAGE_SIZE,
            page: safePage,
            totalPages,
            label: `${start}-${end} of ${total}`,
            previousDisabled: safePage <= 1,
            nextDisabled: safePage >= totalPages
        };
    }

    get actionTitle() {
        const labels = { APPROVE_QUOTE: 'Confirm Quote', REJECT_QUOTE: 'Decline quoted price', CONFIRM_DELIVERY: 'Confirm shipment delivered', DISPUTE_INVOICE: 'Report invoice issue', POD_UPLOAD: 'Upload POD' };
        return labels[this.activeAction] || 'Customer action';
    }
    get actionHelpText() {
        const help = {
            APPROVE_QUOTE: 'Review the quoted amount and confirm it for this shipment.',
            REJECT_QUOTE: 'Decline the quote and add a reason for the transportation team.',
            CONFIRM_DELIVERY: 'Confirm that this shipment has been delivered.',
            DISPUTE_INVOICE: 'Describe the billing issue for the transportation team.',
            POD_UPLOAD: 'Upload the proof of delivery file for this load.'
        };
        return help[this.activeAction] || '';
    }
    get actionMessageLabel() {
        const labels = { APPROVE_QUOTE: 'Confirmation note (optional)', REJECT_QUOTE: 'Reason for declining', CONFIRM_DELIVERY: 'Delivery confirmation note', DISPUTE_INVOICE: 'Invoice issue details', POD_UPLOAD: 'POD note' };
        return labels[this.activeAction] || 'Message';
    }
    get showActionModal() { return !!this.activeAction; }
    get isUploadPodAction() { return this.activeAction === 'POD_UPLOAD'; }
    get actionSubmitLabel() {
        const labels = { APPROVE_QUOTE: 'Confirm Quote', REJECT_QUOTE: 'Decline Quote', CONFIRM_DELIVERY: 'Confirm Delivery', DISPUTE_INVOICE: 'Submit Issue', POD_UPLOAD: 'Upload POD' };
        return labels[this.activeAction] || 'Submit';
    }
    get submitDisabled() {
        if (this.actionInProgress) return true;
        if (this.isUploadPodAction) return !this.selectedFile || !this.selectedFileBase64;
        return false;
    }
    get loginDisabled() { return this.loginInProgress || !this.username || !this.password; }

    handleUsernameChange(event) { this.username = event.target.value; }
    handlePasswordChange(event) { this.password = event.target.value; }
    handleSearchInput(event) { this.searchDraft = event.target.value; }
    handleSearchKeydown(event) { if (event.key === 'Enter') { event.preventDefault(); this.applySearch(); } }
    applySearch() { this.searchTerm = this.searchDraft; this.resetPagination(); }
    clearSearch() { this.searchDraft = ''; this.searchTerm = ''; this.resetPagination(); }
    handleFilterChange(event) { this.statusFilter = event.target.value; this.resetPagination(); }

    handlePageChange(event) {
        const target = event.currentTarget.dataset.target;
        const direction = Number(event.currentTarget.dataset.direction || 0);
        const property = `${target}Page`;
        if (!(property in this)) return;
        const totalMap = {
            dashboard: this.filteredShipments.length,
            current: this.currentShipments.length,
            future: this.futureShipments.length,
            delivered: this.deliveredShipments.length,
            documents: this.filteredDocuments.length,
            invoices: this.filteredInvoices.length
        };
        const maxPage = Math.max(1, Math.ceil((totalMap[target] || 0) / PAGE_SIZE));
        this[property] = Math.max(1, Math.min(maxPage, this[property] + direction));
    }

    async handleLogin(event) {
        event.preventDefault();
        try {
            this.loginInProgress = true;
            this.loginError = null;
            const result = await login({ username: this.username, password: this.password, userAgent: this.getUserAgent() });
            this.sessionKey = result.sessionKey;
            window.localStorage.setItem(SESSION_KEY, this.sessionKey);
            this.password = '';
            this.portalOpenedRecorded = false;
            await this.loadPortal({ preserveLayout: false, useCache: false });
        } catch (error) {
            this.loginError = this.normalizeError(error);
        } finally {
            this.loginInProgress = false;
        }
    }

    async handleLogout() {
        const key = this.sessionKey;
        this.sessionKey = null;
        this.data = null;
        this.error = null;
        this.portalOpenedRecorded = false;
        this.pageCache.clear();
        window.localStorage.removeItem(SESSION_KEY);
        if (key) { try { await logout({ sessionKey: key }); } catch (error) { /* non-blocking */ } }
        window.history.replaceState({}, '', window.location.pathname);
        this.pageName = 'dashboard';
        this.loadId = null;
        this.loading = false;
    }

    async navigate(event) {
        event.preventDefault();
        const page = event.currentTarget.dataset.page;
        const loadId = event.currentTarget.dataset.loadId || null;
        const requestedFilter = event.currentTarget.dataset.filter || 'all';
        const previousPage = this.pageName;
        const requestedDetailSource = page === 'load'
            ? (event.currentTarget.dataset.detailSource || (previousPage === 'shipments' ? 'shipments' : 'dashboard'))
            : 'dashboard';
        if (!page) return;
        if (page === this.pageName && loadId === this.loadId && requestedDetailSource === this.loadDetailSource) return;

        this.pageName = page;
        this.loadId = loadId;
        this.loadDetailSource = requestedDetailSource;
        this.resetViewState();
        this.statusFilter = requestedFilter;
        const sourceParam = page === 'load' && requestedDetailSource === 'shipments' ? '&from=shipments' : '';
        const url = `?p=${encodeURIComponent(page)}${loadId ? `&loadId=${encodeURIComponent(loadId)}` : ''}${sourceParam}`;
        window.history.pushState({}, '', url);
        window.scrollTo({ top: 0, behavior: 'smooth' });
        await this.loadPortal({ preserveLayout: true, useCache: true });
    }

    async loadPortal({ preserveLayout = false, useCache = true } = {}) {
        if (!this.sessionKey) { this.loading = false; return; }
        const cacheKey = `${this.pageName}:${this.loadId || ''}`;
        if (useCache && this.pageCache.has(cacheKey)) {
            this.data = JSON.parse(JSON.stringify(this.pageCache.get(cacheKey)));
            this.loading = false;
            this.contentLoading = false;
            return;
        }

        try {
            if (preserveLayout && this.data) this.contentLoading = true;
            else this.loading = true;
            this.error = null;
            const result = await getPortalData({ sessionKey: this.sessionKey, pageName: this.pageName, loadId: this.loadId });
            this.data = result;
            this.decorateRows();
            this.pageCache.set(cacheKey, JSON.parse(JSON.stringify(this.data)));
            this.recordOpenOnce();
        } catch (error) {
            const message = this.normalizeError(error);
            if (message.toLowerCase().includes('session') || message.toLowerCase().includes('expired')) {
                window.localStorage.removeItem(SESSION_KEY);
                this.sessionKey = null;
                this.data = null;
                this.loginError = message;
            } else {
                this.error = message;
            }
        } finally {
            this.loading = false;
            this.contentLoading = false;
        }
    }

    decorateRows() {
        const clone = this.data ? JSON.parse(JSON.stringify(this.data)) : null;
        if (!clone) return;
        clone.shipments = (clone.shipments || []).map((shipment) => this.decorateShipment(shipment));
        const shipmentById = new Map(clone.shipments.map((shipment) => [shipment.loadId, shipment]));
        if (clone.selectedLoad?.loadId && shipmentById.has(clone.selectedLoad.loadId)) clone.selectedLoad = shipmentById.get(clone.selectedLoad.loadId);
        else if (clone.selectedLoad) clone.selectedLoad = this.decorateShipment(clone.selectedLoad);
        else if (clone.shipments.length) clone.selectedLoad = clone.shipments[0];
        clone.documents = (clone.documents || []).map((document) => ({ ...document, downloadUrl: '#', parentLoad: shipmentById.get(document.loadId) }));
        clone.invoices = (clone.invoices || []).map((invoice) => {
            const status = (invoice.status || '').trim().toLowerCase();
            const toneByStatus = {
                'ready to invoice': 'ready',
                'invoiced': 'invoiced',
                'overdue': 'overdue',
                'payment received': 'paid'
            };
            const tone = toneByStatus[status] || 'not-started';
            return {
                ...invoice,
                parentLoad: shipmentById.get(invoice.loadId) || {},
                statusClassName: `invoice-status ${tone}`,
                actionUrl: this.isUsableUrl(invoice.actionUrl)
                    ? invoice.actionUrl
                    : this.buildPortalPdfUrl(invoice.loadId, 'INVOICE')
            };
        });
        this.data = clone;
    }

    decorateShipment(shipment) {
        const loadId = encodeURIComponent(shipment.loadId || '');
        const pickupMapAddress = this.buildStopAddress(shipment, 'pickup');
        const deliveryMapAddress = this.buildStopAddress(shipment, 'delivery');
        const progress = this.normalizePercent(shipment.routeProgressPercent);
        const mapMarkers = this.buildMapMarkers(shipment);
        const hasTrackingMap = !!(pickupMapAddress && deliveryMapAddress);
        const pendingValue = Object.prototype.hasOwnProperty.call(this.pendingStatuses, shipment.loadId)
            ? this.pendingStatuses[shipment.loadId]
            : (shipment.status === '--None--' ? '__NONE__' : shipment.status);
        const statusTone = this.buildStatusTone(shipment.status);
        const palletCount = this.normalizeNumber(shipment.palletCount);
        const weightLbs = this.normalizeNumber(shipment.weightLbs);
        const routeMarkerPercent = progress === null ? 54 : Math.max(14, Math.min(86, progress));

        return {
            ...shipment,
            bucket: shipment.bucket || this.bucketShipment(shipment),
            statusTone,
            statusValue: pendingValue,
            statusClass: `status-dot ${statusTone}`,
            statusCellClass: `status-cell ${statusTone}`,
            detailStatusClass: this.buildDetailStatusClass(shipment.status),
            shipmentStatusClass: this.buildShipmentStatusClass(shipment.status),
            quoteStatusClass: this.buildQuoteStatusClass(shipment.quoteStatus, shipment.quoteActionAvailable),
            statusProgress: this.buildStatusProgress(shipment.status),
            podLabel: shipment.podReceived ? 'POD received' : 'POD not uploaded',
            detailUrl: `?p=load&loadId=${loadId}`,
            bolUrl: this.isUsableUrl(shipment.bolUrl)
                ? shipment.bolUrl
                : this.buildFtmDocumentUrl(shipment.loadId, 'BOL'),
            invoiceUrl: this.isUsableUrl(shipment.invoiceUrl)
                ? shipment.invoiceUrl
                : this.buildFtmDocumentUrl(shipment.loadId, 'INVOICE'),
            rateUrl: shipment.rateUrl || `apex/RateCon?id=${loadId}`,
            mapMarkers,
            hasTrackingMap,
            progressLabel: progress === null ? '—' : `${progress}%`,
            progressStyle: progress === null ? 'width:0%' : `width:${progress}%`,
            driverPointerStyle: `left:${routeMarkerPercent}%`,
            quantityText: palletCount === null ? '—' : `${this.formatNumber(palletCount)} ${palletCount === 1 ? 'Pallet' : 'Pallets'}`,
            weightText: weightLbs === null ? '—' : `${this.formatNumber(weightLbs)} lbs`,
            pickupLabel: this.buildStopLabel(shipment.pickupCity, shipment.pickupState, 'Pickup'),
            deliveryLabel: this.buildStopLabel(shipment.deliveryCity, shipment.deliveryState, 'Delivery'),
            pickupMapAddress,
            deliveryMapAddress,
            googleMapsUrl: this.buildGoogleMapsRouteUrl(shipment),
            googleMapsEmbedUrl: this.buildGoogleMapsEmbedUrl(shipment),
            statusDirty: pendingValue !== (shipment.status === '--None--' ? '__NONE__' : shipment.status),
            statusSaveDisabled: !pendingValue || pendingValue === (shipment.status === '--None--' ? '__NONE__' : shipment.status) || this.savingLoadId === shipment.loadId,
            statusSaving: this.savingLoadId === shipment.loadId
        };
    }

    buildStatusTone(status) {
        const normalized = (status || '').trim().toLowerCase();
        if (normalized.includes('deliver')) return 'delivered';
        if (normalized.includes('delay') || normalized.includes('cancel') || normalized.includes('hold')) return 'attention';
        if (!normalized || normalized === '--none--' || normalized === 'assigned' || normalized === 'dispatched') return 'future';
        return 'transit';
    }

    buildDetailStatusClass(status) {
        const normalized = (status || '').trim().toLowerCase();
        if (normalized.includes('deliver')) return 'load-status-banner delivered';
        if (normalized.includes('delay') || normalized.includes('cancel') || normalized.includes('hold')) return 'load-status-banner attention';
        if (normalized === 'assigned' || normalized === 'dispatched' || !normalized || normalized === '--none--') return 'load-status-banner future';
        return 'load-status-banner transit';
    }

    buildQuoteStatusClass(status, actionAvailable) {
        const normalized = (status || '').trim().toLowerCase();
        if (normalized === 'approved') return 'quote-status accepted';
        if (normalized === 'rejected') return 'quote-status declined';
        if (actionAvailable) return 'quote-status pending';
        return 'quote-status neutral';
    }

    buildShipmentStatusClass(status) {
        const normalized = (status || '').trim().toLowerCase();
        if (normalized.includes('deliver')) return 'shipment-status-pill delivered';
        if (normalized.includes('delay') || normalized.includes('cancel') || normalized.includes('hold')) return 'shipment-status-pill attention';
        if (normalized === 'assigned' || normalized === 'dispatched' || !normalized || normalized === '--none--') return 'shipment-status-pill future';
        return 'shipment-status-pill transit';
    }

    buildStatusProgress(status) {
        const steps = [
            { value: 'assigned', label: 'Assigned' },
            { value: 'dispatched', label: 'Dispatched' },
            { value: 'in transit to pickup', label: 'To Pickup' },
            { value: 'at shipping', label: 'At Shipping' },
            { value: 'in transit to delivery', label: 'To Delivery' },
            { value: 'at receiving', label: 'At Receiving' },
            { value: 'delivered', label: 'Delivered' }
        ];
        const normalized = (status || '').trim().toLowerCase();
        let currentIndex = steps.findIndex((step) => step.value === normalized);
        if (currentIndex < 0 && normalized.includes('deliver')) currentIndex = steps.length - 1;

        return steps.map((step, index) => {
            const complete = currentIndex >= 0 && index < currentIndex;
            const current = index === currentIndex;
            return {
                ...step,
                marker: complete ? '✓' : `${index + 1}`,
                className: `progress-step ${complete ? 'complete' : (current ? 'current' : 'upcoming')}`
            };
        });
    }

    buildMapMarkers(shipment) {
        const markers = [];
        if (shipment.pickupCity || shipment.pickupState) markers.push({ location: { City: shipment.pickupCity || '', State: shipment.pickupState || '' }, title: 'Pickup', description: shipment.pickupText || shipment.route || '' });
        if (shipment.driverLatitude !== null && shipment.driverLatitude !== undefined && shipment.driverLongitude !== null && shipment.driverLongitude !== undefined) markers.push({ location: { Latitude: Number(shipment.driverLatitude), Longitude: Number(shipment.driverLongitude) }, title: 'Driver location', description: shipment.driverLocationText || '' });
        if (shipment.deliveryCity || shipment.deliveryState) markers.push({ location: { City: shipment.deliveryCity || '', State: shipment.deliveryState || '' }, title: 'Delivery', description: shipment.deliveryText || shipment.route || '' });
        return markers;
    }
    buildStopLabel(city, state, fallback) { const parts = [city, state].filter(Boolean); return parts.length ? parts.join(', ') : fallback; }
    buildStopAddress(shipment, prefix) {
        const addressLine = shipment[`${prefix}AddressLine`];
        const cityStateZip = shipment[`${prefix}CityStateZip`];
        const fallback = this.buildStopLabel(shipment[`${prefix}City`], shipment[`${prefix}State`], '');
        return [addressLine && addressLine !== '—' ? addressLine : '', cityStateZip && cityStateZip !== '—' ? cityStateZip : fallback].filter(Boolean).join(', ');
    }
    buildGoogleMapsRouteUrl(shipment) {
        const originText = this.buildStopAddress(shipment, 'pickup');
        const destinationText = this.buildStopAddress(shipment, 'delivery');
        if (!originText || !destinationText) return '#';
        const origin = encodeURIComponent(originText);
        const destination = encodeURIComponent(destinationText);
        const hasDriver = shipment.driverLatitude !== null && shipment.driverLatitude !== undefined && shipment.driverLongitude !== null && shipment.driverLongitude !== undefined;
        const waypoint = hasDriver ? `&waypoints=${encodeURIComponent(`${shipment.driverLatitude},${shipment.driverLongitude}`)}` : '';
        return `https://www.google.com/maps/dir/?api=1&origin=${origin}&destination=${destination}${waypoint}&travelmode=driving`;
    }
    buildGoogleMapsEmbedUrl(shipment) {
        const pickup = this.buildStopAddress(shipment, 'pickup') || this.buildStopLabel(shipment.pickupCity, shipment.pickupState, '');
        const delivery = this.buildStopAddress(shipment, 'delivery') || this.buildStopLabel(shipment.deliveryCity, shipment.deliveryState, '');
        if (!pickup || !delivery) return '';

        const hasDriver = shipment.driverLatitude !== null && shipment.driverLatitude !== undefined
            && shipment.driverLongitude !== null && shipment.driverLongitude !== undefined;
        const driver = hasDriver ? `${shipment.driverLatitude},${shipment.driverLongitude}` : '';
        const routeDestination = driver ? `${driver} to:${delivery}` : delivery;

        return `https://maps.google.com/maps?f=d&source=s_d&saddr=${encodeURIComponent(pickup)}&daddr=${encodeURIComponent(routeDestination)}&hl=en&dirflg=d&output=embed`;
    }
    normalizeNumber(value) { if (value === null || value === undefined || value === '') return null; const numberValue = Number(value); return Number.isNaN(numberValue) ? null : numberValue; }
    formatNumber(value) { return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(value); }
    normalizePercent(value) { if (value === null || value === undefined || value === '') return null; const numberValue = Number(value); return Number.isNaN(numberValue) ? null : Math.max(0, Math.min(100, Math.round(numberValue))); }
    matchesSearch(shipment) { const term = this.normalizedSearch; return !term || `${shipment.loadNumber || ''} ${shipment.route || ''} ${shipment.status || ''} ${shipment.pickupText || ''} ${shipment.deliveryText || ''}`.toLowerCase().includes(term); }
    matchesStatusFilter(shipment) {
        if (this.statusFilter === 'all') return true;
        if (this.statusFilter === 'active') return shipment.bucket !== 'delivered';
        if (this.statusFilter === 'delivered') return shipment.bucket === 'delivered';
        if (this.statusFilter === 'transit') return shipment.bucket === 'current';
        if (this.statusFilter === 'delayed') return (shipment.status || '').toLowerCase().includes('delay');
        return true;
    }
    bucketShipment(shipment) { const status = (shipment.status || '').toLowerCase(); if (status.includes('deliver')) return 'delivered'; return ['in transit to pickup', 'at shipping', 'in transit to delivery', 'at receiving'].includes(status) ? 'current' : 'future'; }

    handleStatusSelection(event) {
        const loadId = event.currentTarget.dataset.loadId;
        if (!loadId) return;
        this.pendingStatuses = { ...this.pendingStatuses, [loadId]: event.target.value };
        this.decorateRows();
    }

    async saveStatus(event) {
        const loadId = event.currentTarget.dataset.loadId;
        const loadNumber = event.currentTarget.dataset.loadNumber;
        const selectedValue = this.pendingStatuses[loadId];
        if (!loadId || selectedValue === undefined || !this.sessionKey) return;
        const statusValue = selectedValue === '__NONE__' ? '' : selectedValue;
        try {
            this.savingLoadId = loadId;
            this.actionMessage = `Saving status for ${loadNumber || 'load'}...`;
            this.decorateRows();
            await updateLoadStatus({ sessionKey: this.sessionKey, loadId, statusValue, userAgent: this.getUserAgent() });
            this.updateStatusLocally(loadId, statusValue || '--None--');
            const copy = { ...this.pendingStatuses };
            delete copy[loadId];
            this.pendingStatuses = copy;
            this.pageCache.clear();
            this.actionMessage = 'Status saved.';
        } catch (error) {
            this.actionMessage = this.normalizeError(error);
        } finally {
            this.savingLoadId = null;
            this.decorateRows();
        }
    }

    updateStatusLocally(loadId, status) {
        const clone = JSON.parse(JSON.stringify(this.data || {}));
        clone.shipments = (clone.shipments || []).map((item) => item.loadId === loadId ? { ...item, status, bucket: this.bucketShipment({ status }) } : item);
        if (clone.selectedLoad?.loadId === loadId) clone.selectedLoad = { ...clone.selectedLoad, status, bucket: this.bucketShipment({ status }) };
        this.data = clone;
    }

    async recordOpenOnce() {
        if (this.portalOpenedRecorded || !this.sessionKey) return;
        this.portalOpenedRecorded = true;
        try { await recordPortalOpened({ sessionKey: this.sessionKey, userAgent: this.getUserAgent() }); } catch (error) { /* non-blocking */ }
    }

    openAction(event) {
        this.activeAction = event.currentTarget.dataset.action;
        this.activeLoadId = event.currentTarget.dataset.loadId;
        this.activeLoadNumber = event.currentTarget.dataset.loadNumber;
        this.messageValue = '';
        this.selectedFile = null;
        this.selectedFileBase64 = null;
        this.actionMessage = null;
    }
    closeAction() { if (this.actionInProgress) return; this.activeAction = null; this.activeLoadId = null; this.activeLoadNumber = null; this.messageValue = ''; this.selectedFile = null; this.selectedFileBase64 = null; }
    handleMessageChange(event) { this.messageValue = event.target.value; }
    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (file.size > 6 * 1024 * 1024) { this.actionMessage = 'File is too large. Use a file smaller than 6 MB.'; return; }
        this.selectedFile = file;
        const reader = new FileReader();
        reader.onload = () => { this.selectedFileBase64 = reader.result; this.actionMessage = `Selected file: ${file.name}`; };
        reader.onerror = () => { this.actionMessage = 'Could not read the selected file.'; this.selectedFile = null; this.selectedFileBase64 = null; };
        reader.readAsDataURL(file);
    }
    async submitAction() {
        if (!this.activeAction || !this.activeLoadId || !this.sessionKey) return;
        try {
            this.actionInProgress = true;
            this.actionMessage = 'Submitting...';
            if (this.isUploadPodAction) await uploadPod({ sessionKey: this.sessionKey, loadId: this.activeLoadId, fileName: this.selectedFile.name, base64Data: this.selectedFileBase64, message: this.messageValue, userAgent: this.getUserAgent() });
            else await submitCustomerAction({ sessionKey: this.sessionKey, loadId: this.activeLoadId, actionName: this.activeAction, message: this.messageValue, userAgent: this.getUserAgent() });
            this.pageCache.clear();
            await this.loadPortal({ preserveLayout: true, useCache: false });
            this.closeAction();
            this.actionMessage = 'Done.';
        } catch (error) { this.actionMessage = this.normalizeError(error); }
        finally { this.actionInProgress = false; }
    }

    async openDocument(event) {
        const documentId = event.currentTarget.dataset.documentId;
        const versionId = event.currentTarget.dataset.versionId;
        const loadId = event.currentTarget.dataset.loadId;
        try {
            const url = await getDocumentDownloadUrl({ sessionKey: this.sessionKey, versionId, loadId });
            try { await recordDocumentViewed({ sessionKey: this.sessionKey, documentId, loadId, userAgent: this.getUserAgent() }); } catch (logError) { /* non-blocking */ }
            this.openUrlValue(url);
        } catch (error) { this.actionMessage = this.normalizeError(error); }
    }
    openUrl(event) { this.openUrlValue(event.currentTarget.dataset.url); }
    openUrlValue(url) {
        if (!this.isUsableUrl(url)) {
            this.actionMessage = 'This document link is not available.';
            return;
        }
        const openedWindow = window.open(url, '_blank', 'noopener,noreferrer');
        if (!openedWindow) window.location.assign(url);
    }
    isUsableUrl(url) { return !!url && url !== '#'; }
    buildFtmDocumentUrl(loadId, documentType) {
        if (!loadId) return '#';
        const siteBasePath = this.getSiteBasePath();
        const pageName = documentType === 'INVOICE' ? 'FreightTM__Invoice' : 'FreightTM__BOL';
        const query = new URLSearchParams({ id: String(loadId) });
        return `${window.location.origin}${siteBasePath}/apex/${pageName}?${query.toString()}`;
    }
    getSiteBasePath() {
        let path = window.location.pathname || '';
        path = path.replace(/\/$/, '');
        path = path.replace(/\/apex\/CustomerPortal$/i, '');
        path = path.replace(/\/CustomerPortal$/i, '');
        return path;
    }
    getUserAgent() { return `${navigator.platform || ''} ${navigator.userAgent || ''}`.substring(0, 255); }
    normalizeError(error) {
        if (!error) return 'Something went wrong.';
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
        if (error.body && typeof error.body.message === 'string') return error.body.message;
        if (typeof error.message === 'string') return error.message;
        return 'Something went wrong.';
    }
    resetPagination() { this.dashboardPage = 1; this.currentPage = 1; this.futurePage = 1; this.deliveredPage = 1; this.documentsPage = 1; this.invoicesPage = 1; }
    resetViewState() { this.searchDraft = ''; this.searchTerm = ''; this.statusFilter = 'all'; this.pendingStatuses = {}; this.actionMessage = null; this.resetPagination(); }
}