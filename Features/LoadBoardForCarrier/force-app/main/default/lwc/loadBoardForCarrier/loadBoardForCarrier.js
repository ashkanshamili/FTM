import { LightningElement } from 'lwc';

import loginCarrier from '@salesforce/apex/LoadBoardForCarrierController.loginCarrier';
import refreshLoadBoard from '@salesforce/apex/LoadBoardForCarrierController.refreshLoadBoard';
import createBid from '@salesforce/apex/LoadBoardForCarrierController.createBid';
import getMyBids from '@salesforce/apex/LoadBoardForCarrierController.getMyBids';
import getAssignedLoads from '@salesforce/apex/LoadBoardForCarrierController.getAssignedLoads';
import FTM_LOGO from '@salesforce/resourceUrl/FTM_Logo';

const SESSION_STORAGE_KEY = 'ftmCarrierLoadBoardSession';
const PAGE_SIZE = 10;

export default class LoadBoardForCarrier
    extends LightningElement {
        ftmLogoUrl = FTM_LOGO;

    isLoading = false;
    isAuthenticated = false;

    loginCarrierName = '';
    loginMcNumber = '';

    carrierId;
    carrierName;
    mcNumber;

    loads = [];
    filteredLoads = [];

    searchTerm = '';
    appliedSearchTerm = '';
    errorMessage = '';
    successMessage = '';

    submittedBidCount = 0;
    showMyBids = false;
    myBids = [];

    showAssignedLoads = false;
    assignedLoads = [];

    currentPage = 1;
    pageSize = PAGE_SIZE;

    connectedCallback() {
        this.restoreSession();
    }

    get showOpenOpportunities() {
    return (
        !this.showMyBids &&
        !this.showAssignedLoads
    );
}

get hasAssignedLoads() {
    return this.assignedLoads.length > 0;
}

get assignedLoadCountLabel() {
    const count =
        this.assignedLoads.length;

    return `${count} ${
        count === 1
            ? 'load'
            : 'loads'
    }`;
}

get hasMyBids() {
    return this.myBids.length > 0;
}

get myBidCountLabel() {
    const count =
        this.myBids.length;

    return `${count} ${
        count === 1
            ? 'bid'
            : 'bids'
    }`;
}

    get disableLoginButton() {
        return (
            this.isLoading ||
            !this.loginCarrierName.trim() ||
            !this.loginMcNumber.trim()
        );
    }

    get openOpportunityCount() {
        return this.loads.length;
    }

    get hasFilteredLoads() {
        return this.filteredLoads.length > 0;
    }

    get filteredLoadCountLabel() {
        const count =
            this.filteredLoads.length;

        return `${count} ${
            count === 1
                ? 'load'
                : 'loads'
        }`;
    }

    get totalPages() {
        return Math.max(
            1,
            Math.ceil(
                this.filteredLoads.length /
                this.pageSize
            )
        );
    }

    get paginatedLoads() {
        const startIndex =
            (this.currentPage - 1) *
            this.pageSize;

        return this.filteredLoads.slice(
            startIndex,
            startIndex + this.pageSize
        );
    }

    get showPagination() {
        return this.filteredLoads.length >
            this.pageSize;
    }

    get disablePreviousPage() {
        return this.currentPage <= 1;
    }

    get disableNextPage() {
        return this.currentPage >=
            this.totalPages;
    }

    get pageIndicator() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get paginationSummary() {
        const total =
            this.filteredLoads.length;

        if (!total) {
            return 'Showing 0 loads';
        }

        const start =
            ((this.currentPage - 1) *
                this.pageSize) + 1;

        const end = Math.min(
            this.currentPage * this.pageSize,
            total
        );

        return `Showing ${start}-${end} of ${total} loads`;
    }

    async handleShowAssignedLoads() {
    if (
        !this.isAuthenticated ||
        !this.carrierId
    ) {
        return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.successMessage = '';

    try {
        const response =
            await getAssignedLoads({
                carrierId:
                    this.carrierId,

                carrierName:
                    this.carrierName,

                mcNumber:
                    this.mcNumber
            });

        this.assignedLoads =
            (
                response?.loads || []
            ).map((load) =>
                this.decorateAssignedLoad(
                    load
                )
            );

        this.showMyBids = false;
        this.showAssignedLoads = true;

    } catch (error) {
        this.errorMessage =
            this.getErrorMessage(
                error
            );

    } finally {
        this.isLoading = false;
    }
}

decorateAssignedLoad(load) {
    return {
        ...load,

        trailerDisplay:
            load.trailerType ||
            'Trailer not specified',

        pickupAddressDisplay:
            load.pickupAddress ||
            'Pickup not specified',

        pickupDateDisplay:
            this.formatDate(
                load.pickupDate
            ),

        weightDisplay:
            load.weight !== null &&
            load.weight !== undefined
                ? `${this.formatNumber(
                    load.weight
                )} lb`
                : 'Weight not specified',

        rateDisplay:
            this.formatCurrency(
                load.rate
            ),

        statusDisplay:
            load.status ||
            'Not specified'
    };
}

    async handleShowMyBids() {
    if (
        !this.isAuthenticated ||
        !this.carrierId
    ) {
        return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.successMessage = '';

    try {
        const response =
            await getMyBids({
                carrierId:
                    this.carrierId,

                carrierName:
                    this.carrierName,

                mcNumber:
                    this.mcNumber
            });

        this.myBids =
            (
                response?.bids || []
            ).map((bid) =>
                this.decorateBid(bid)
            );

        this.submittedBidCount =
            response?.submittedBidCount ||
            this.myBids.length;
        this.showAssignedLoads = false;
        this.showMyBids = true;

    } catch (error) {
        this.errorMessage =
            this.getErrorMessage(
                error
            );

    } finally {
        this.isLoading = false;
    }
}

handleShowOpenOpportunities() {
    this.showMyBids = false;
    this.showAssignedLoads = false;
    this.errorMessage = '';
    this.successMessage = '';
}

decorateBid(bid) {
    return {
        ...bid,

        rateDisplay:
            this.formatCurrency(
                bid.rate
            ),

        transitTimeDisplay:
            bid.transitTime
                ? `${bid.transitTime} ${
                    Number(bid.transitTime) === 1
                        ? 'day'
                        : 'days'
                }`
                : 'Not provided',

        submittedDateDisplay:
            this.formatDateTime(
                bid.submittedDate
            )
    };
}

formatCurrency(value) {
    if (
        value === null ||
        value === undefined ||
        value === ''
    ) {
        return '—';
    }

    return new Intl.NumberFormat(
        'en-US',
        {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }
    ).format(
        Number(value)
    );
}

formatDateTime(value) {
    if (!value) {
        return 'Not provided';
    }

    const dateValue =
        new Date(value);

    if (
        Number.isNaN(
            dateValue.getTime()
        )
    ) {
        return 'Not provided';
    }

    return new Intl.DateTimeFormat(
        'en-US',
        {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }
    ).format(dateValue);
}

    handleLoginFieldChange(event) {
        const {
            name,
            value
        } = event.target;

        if (name === 'carrierName') {
            this.loginCarrierName =
                value;
        }

        if (name === 'mcNumber') {
            this.loginMcNumber =
                value;
        }

        this.errorMessage = '';
    }

    async handleLogin(event) {
        event.preventDefault();

        this.errorMessage = '';
        this.successMessage = '';

        const carrierName =
            String(
                this.loginCarrierName || ''
            ).trim();

        const mcNumber =
            String(
                this.loginMcNumber || ''
            ).trim();

        if (
            !carrierName ||
            !mcNumber
        ) {
            this.errorMessage =
                'Enter both the carrier name and MC number.';

            return;
        }

        this.isLoading = true;

        try {
            const response =
                await loginCarrier({
                    carrierName,
                    mcNumber
                });

            this.applyLoadBoardResponse(
                response
            );

            this.isAuthenticated = true;

            this.saveSession();

        } catch (error) {
            this.errorMessage =
                this.getErrorMessage(
                    error
                );

            this.clearSession();

        } finally {
            this.isLoading = false;
        }
    }

    async handleRefresh() {
    if (!this.isAuthenticated) {
        return;
    }

    if (this.showAssignedLoads) {
        await this.handleShowAssignedLoads();
        return;
    }

    if (this.showMyBids) {
        await this.handleShowMyBids();
        return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.successMessage = '';

    try {
        const response =
            await refreshLoadBoard({
                carrierId:
                    this.carrierId,

                carrierName:
                    this.carrierName,

                mcNumber:
                    this.mcNumber
            });

        this.applyLoadBoardResponse(
            response
        );

    } catch (error) {
        this.errorMessage =
            this.getErrorMessage(
                error
            );

        const normalizedError =
            this.errorMessage
                .toLowerCase();

        if (
            normalizedError.includes(
                'sign in again'
            ) ||
            normalizedError.includes(
                'session'
            )
        ) {
            this.handleLogout();
        }

    } finally {
        this.isLoading = false;
    }
}

    handleSearch(event) {
        this.searchTerm =
            event.target.value || '';

        //this.applyFilter(true);
    }

    handleApplyFilter() {
    this.appliedSearchTerm =
        String(
            this.searchTerm || ''
        ).trim();

    this.applyFilter(true);
}

handleClearFilter() {
    this.searchTerm = '';
    this.appliedSearchTerm = '';

    this.applyFilter(true);
}

    handlePreviousPage() {
        if (this.disablePreviousPage) {
            return;
        }

        this.currentPage -= 1;
        this.focusLoadTable();
    }

    handleNextPage() {
        if (this.disableNextPage) {
            return;
        }

        this.currentPage += 1;
        this.focusLoadTable();
    }

    focusLoadTable() {
        requestAnimationFrame(() => {
            const table =
                this.template.querySelector(
                    '.load-table-shell'
                );

            if (table) {
                table.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    }

    handleLoadBidFieldChange(event) {
        const loadId =
            event.currentTarget
                .dataset
                .loadId;

        const fieldName =
            event.currentTarget.name;

        const value =
            event.currentTarget.value;

        this.updateLoad(
            loadId,
            {
                [fieldName]: value,
                bidError: ''
            }
        );
    }

    async handleSubmitBid(event) {
        this.successMessage = '';

        const loadId =
            event.currentTarget
                .dataset
                .loadId;

        const load =
            this.loads.find(
                (item) =>
                    item.loadId === loadId
            );

        if (!load) {
            this.errorMessage =
                'The selected load could not be found.';

            return;
        }

        if (!this.carrierId) {
            this.updateLoad(
                loadId,
                {
                    bidError:
                        'Your carrier session is missing. Please log out and sign in again.'
                }
            );

            return;
        }

        const parsedTransitTime =
            Number(
                load.bidTransitTime
            );

        if (
            !Number.isInteger(
                parsedTransitTime
            ) ||
            parsedTransitTime <= 0
        ) {
            this.updateLoad(
                loadId,
                {
                    bidError:
                        'Enter a valid whole-number transit time greater than zero.'
                }
            );

            return;
        }

        if (
            !load.bidTransitionDate
        ) {
            this.updateLoad(
                loadId,
                {
                    bidError:
                        'Enter a transition date and time.'
                }
            );

            return;
        }

        const transitionDateValue =
            new Date(
                load.bidTransitionDate
            );

        if (
            Number.isNaN(
                transitionDateValue
                    .getTime()
            )
        ) {
            this.updateLoad(
                loadId,
                {
                    bidError:
                        'Enter a valid transition date and time.'
                }
            );

            return;
        }

        const parsedRate =
            Number(
                load.bidRate
            );

        if (
            !Number.isFinite(
                parsedRate
            ) ||
            parsedRate <= 0
        ) {
            this.updateLoad(
                loadId,
                {
                    bidError:
                        'Enter a valid rate greater than zero.'
                }
            );

            return;
        }

        this.updateLoad(
            loadId,
            {
                isSubmittingBid: true,
                bidError: '',
                bidSuccess: ''
            }
        );

        try {
    const response =
        await createBid({
            carrierId:
                this.carrierId,

            loadId,

            rate:
                parsedRate,

            transitionDate:
                transitionDateValue
                    .toISOString(),

            transitTime:
                String(
                    parsedTransitTime
                )
        });

    const successText =
        `Bid for ${load.loadName} was submitted successfully.`;

    this.submittedBidCount += 1;

    this.updateLoad(
        loadId,
        {
            isSubmittingBid: false,
            bidError: '',
            bidSuccess: successText
        }
    );

    window.setTimeout(() => {
        this.loads =
            this.loads.filter(
                (item) =>
                    item.loadId !== loadId
            );

        this.applyFilter();
    }, 2500);

} catch (error) {
    this.updateLoad(
        loadId,
        {
            isSubmittingBid: false,
            bidSuccess: '',
            bidError:
                this.getErrorMessage(
                    error
                )
        }
    );
}
    }

    handleLogout() {
        this.isAuthenticated = false;

        this.carrierId = undefined;
        this.carrierName = undefined;
        this.mcNumber = undefined;

        this.loginCarrierName = '';
        this.loginMcNumber = '';

        this.loads = [];
        this.filteredLoads = [];

        this.searchTerm = '';
        this.appliedSearchTerm = '';
        this.errorMessage = '';
        this.successMessage = '';

        this.submittedBidCount = 0;
        this.currentPage = 1;

        this.showMyBids = false;
        this.myBids = [];

        this.showAssignedLoads = false;
        this.assignedLoads = [];

        this.clearSession();
    }

    applyLoadBoardResponse(response) {
    if (!response?.carrier) {
        throw new Error(
            'The server returned an invalid response.'
        );
    }

    this.carrierId =
        response
            .carrier
            .carrierId;

    this.carrierName =
        response
            .carrier
            .carrierName;

    this.mcNumber =
        response
            .carrier
            .mcNumber;

    this.loads =
        (
            response.loads || []
        ).map(
            (load) =>
                this.decorateLoad(
                    load
                )
        );

    this.submittedBidCount =
        response.submittedBidCount || 0;

    this.applyFilter(true);
}

    applyFilter(resetPage = false) {
        const normalizedSearch =
            this.normalizeText(
                this.appliedSearchTerm
            );

        if (!normalizedSearch) {
            this.filteredLoads = [
                ...this.loads
            ];
        } else {
            this.filteredLoads =
                this.loads.filter(
                    (load) => {
                        const searchableValues = [
                            load.loadName,
                            load.lane,
                            load.pickupCity,
                            load.pickupState,
                            this.firstThreeCharacters(
                                load.pickupZip
                            ),
                            load.trailerType
                        ];

                        return searchableValues
                            .some(
                                (value) =>
                                    this
                                        .normalizeText(
                                            value
                                        )
                                        .includes(
                                            normalizedSearch
                                        )
                            );
                    }
                );
        }

        if (resetPage) {
            this.currentPage = 1;
        }

        this.ensureValidCurrentPage();
    }

    ensureValidCurrentPage() {
        if (this.currentPage > this.totalPages) {
            this.currentPage = this.totalPages;
        }

        if (this.currentPage < 1) {
            this.currentPage = 1;
        }
    }

    decorateLoad(load) {
        return {
            ...load,

            pickupDateDisplay:
                this.formatDate(
                    load.pickupDate
                ),

            deliveryDateDisplay:
                this.formatDate(
                    load.deliveryDate
                ),

            trailerDisplay:
                load.trailerType ||
                'Trailer not specified',

            weightDisplay:
                load.weight !== null &&
                load.weight !== undefined
                    ? `${this.formatNumber(
                        load.weight
                    )} lb`
                    : 'Weight not specified',

            /*
             * Editable values for this Load row.
             */
            bidTransitTime: '',

            bidTransitionDate:
                this
                    .getDefaultTransitionDate(),

            bidRate: '',

            isSubmittingBid: false,

            bidError: '',
            bidSuccess: ''
        };
    }

    updateLoad(
        loadId,
        changes
    ) {
        this.loads =
            this.loads.map(
                (load) =>
                    load.loadId === loadId
                        ? {
                            ...load,
                            ...changes
                        }
                        : load
            );

        this.applyFilter();
    }

    formatDate(value) {
        if (!value) {
            return 'Date not specified';
        }

        const parsedDate =
            new Date(
                `${value}T00:00:00`
            );

        if (
            Number.isNaN(
                parsedDate.getTime()
            )
        ) {
            return value;
        }

        return new Intl
            .DateTimeFormat(
                'en-US',
                {
                    month: 'short',
                    day: 'numeric',
                    year: 'numeric'
                }
            )
            .format(
                parsedDate
            );
    }

    formatNumber(value) {
        return new Intl
            .NumberFormat(
                'en-US',
                {
                    maximumFractionDigits:
                        2
                }
            )
            .format(
                value
            );
    }

    getDefaultTransitionDate() {
        const now =
            new Date();

        const offsetMilliseconds =
            now.getTimezoneOffset() *
            60 *
            1000;

        return new Date(
            now.getTime() -
            offsetMilliseconds
        )
            .toISOString()
            .slice(
                0,
                16
            );
    }

    normalizeText(value) {
        return String(
            value || ''
        )
            .trim()
            .toLowerCase();
    }

    firstThreeCharacters(value) {
        return String(
            value || ''
        )
            .trim()
            .substring(
                0,
                3
            );
    }

    saveSession() {
        try {
            sessionStorage.setItem(
                SESSION_STORAGE_KEY,

                JSON.stringify({
                    carrierId:
                        this.carrierId,

                    carrierName:
                        this.carrierName,

                    mcNumber:
                        this.mcNumber
                })
            );

        } catch (error) {
            /*
             * Continue when browser storage
             * is unavailable.
             */
        }
    }

    async restoreSession() {
        let savedSession;

        try {
            const serializedSession =
                sessionStorage.getItem(
                    SESSION_STORAGE_KEY
                );

            if (!serializedSession) {
                return;
            }

            savedSession =
                JSON.parse(
                    serializedSession
                );

        } catch (error) {
            this.clearSession();
            return;
        }

        if (
            !savedSession?.carrierId ||
            !savedSession?.carrierName ||
            !savedSession?.mcNumber
        ) {
            this.clearSession();
            return;
        }

        this.carrierId =
            savedSession.carrierId;

        this.carrierName =
            savedSession.carrierName;

        this.mcNumber =
            savedSession.mcNumber;

        this.isLoading = true;

        try {
            const response =
                await refreshLoadBoard({
                    carrierId:
                        this.carrierId,

                    carrierName:
                        this.carrierName,

                    mcNumber:
                        this.mcNumber
                });

            this.applyLoadBoardResponse(
                response
            );

            this.isAuthenticated = true;

        } catch (error) {
            this.clearSession();

            this.isAuthenticated =
                false;

        } finally {
            this.isLoading = false;
        }
    }

    clearSession() {
        try {
            sessionStorage.removeItem(
                SESSION_STORAGE_KEY
            );

        } catch (error) {
            // No action is required.
        }
    }

    getErrorMessage(error) {
        console.error(
            'Carrier Load Board error:',
            error
        );

        if (!error) {
            return (
                'An unexpected error occurred. ' +
                'Please try again.'
            );
        }

        if (
            typeof error === 'string'
        ) {
            return error;
        }

        if (
            typeof error.body ===
            'string'
        ) {
            return error.body;
        }

        if (
            Array.isArray(
                error.body
            )
        ) {
            const messages =
                error.body
                    .map(
                        (item) =>
                            item?.message
                    )
                    .filter(
                        Boolean
                    );

            if (messages.length) {
                return messages.join(
                    ', '
                );
            }
        }

        if (
            error.body?.message
        ) {
            return error.body.message;
        }

        if (
            error.message
        ) {
            return error.message;
        }

        return (
            'An unexpected error occurred. ' +
            'Please try again.'
        );
    }
}

/*sf project deploy start `
    --source-dir "force-app/main/default/lwc/loadBoardForCarrier" `
    --target-org "CarrierLoadBoardProduction" `
    --wait 30
*/