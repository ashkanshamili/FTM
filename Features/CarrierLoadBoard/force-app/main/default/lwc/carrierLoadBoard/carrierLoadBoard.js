import {
    LightningElement,
    api
} from 'lwc';

import getLoadBoardData from
    '@salesforce/apex/CarrierLoadBoardController.getLoadBoardData';

import getLoadDetails from
    '@salesforce/apex/CarrierLoadBoardController.getLoadDetails';

import assignBid from
    '@salesforce/apex/CarrierLoadBoardController.assignBid';

import FTM_LOGO from '@salesforce/resourceUrl/FTM_Logo';

export default class CarrierLoadBoard
    extends LightningElement {

    @api recordId;
    ftmLogoUrl = FTM_LOGO;

    loads = [];
    searchText = '';

    openOpportunityCount = 0;
    approvedCarrierCount = 0;
    averageResponseDisplay = '—';

    selectedLoad;
    showDetailsModal = false;

    selectedBid;
    showBidModal = false;

    bidModalError;
    bidModalMessage;
    assignmentCompleted = false;

    successMessage;
    errorMessage;

    loading = false;
    assigningBid = false;

    connectedCallback() {
        this.loadBoardData();
    }

    get filteredLoads() {
        const search =
            String(this.searchText || '')
                .trim()
                .toLowerCase();

        if (!search) {
            return this.loads;
        }

        return this.loads.filter((load) => {
            const bidValues =
                (load.bids || []).flatMap((bid) => [
                    bid.bidName,
                    bid.carrierName,
                    bid.contactDisplay,
                    bid.emailDisplay,
                    bid.rateDisplay,
                    bid.transitTimeDisplay
                ]);

            const values = [
                load.loadNumber,
                load.origin,
                load.destination,
                load.trailerDisplay,
                load.commodityDisplay,
                load.requirements,
                ...bidValues
            ];

            return values.some((value) =>
                String(value || '')
                    .toLowerCase()
                    .includes(search)
            );
        });
    }

    get hasLoads() {
        return (
            !this.loading &&
            this.filteredLoads.length > 0
        );
    }

    get showEmptyState() {
        return (
            !this.loading &&
            !this.errorMessage &&
            this.filteredLoads.length === 0
        );
    }

    get disableAssignBid() {
        return (
            this.assigningBid ||
            this.assignmentCompleted ||
            !this.selectedBid ||
            !this.selectedBid.bidId ||
            !this.selectedBid.loadId
        );
    }

    get showAssignButton() {
    return !this.assignmentCompleted;
}

    async loadBoardData() {
        this.loading = true;
        this.errorMessage = undefined;

        try {
            const result =
                await getLoadBoardData({
                    currentLoadId:
                        this.recordId || null
                });

            this.openOpportunityCount =
                result?.openOpportunityCount || 0;

            this.approvedCarrierCount =
                result?.approvedCarrierCount || 0;

            this.averageResponseDisplay =
                result?.averageResponseDisplay || '—';

            const rawLoads =
                Array.isArray(result?.loads)
                    ? result.loads
                    : [];

            this.loads =
                rawLoads.map((load) =>
                    this.decorateLoad(load)
                );

        } catch (error) {
            this.errorMessage =
                this.reduceError(error);

        } finally {
            this.loading = false;
        }
    }

    async handleViewDetails(event) {
        const loadId =
            event.currentTarget.dataset.loadId;

        this.loading = true;
        this.errorMessage = undefined;

        try {
            const result =
                await getLoadDetails({
                    loadId
                });

            this.selectedLoad =
                this.decorateLoad(result);

            this.showDetailsModal = true;

        } catch (error) {
            this.errorMessage =
                this.reduceError(error);

        } finally {
            this.loading = false;
        }
    }

    handleBidClick(event) {
        const loadId =
            event.currentTarget.dataset.loadId;

        const bidId =
            event.currentTarget.dataset.bidId;

        const load =
            this.loads.find(
                (item) => item.loadId === loadId
            );

        if (!load) {
            this.errorMessage =
                'The selected load could not be found.';
            return;
        }

        const bid =
            (load.bids || []).find(
                (item) => item.bidId === bidId
            );

        if (!bid) {
            this.errorMessage =
                'The selected bid could not be found.';
            return;
        }

        this.selectedBid = {
            ...bid,
            loadId: load.loadId,
            loadNumber: load.loadNumber,
            lane:
                `${load.origin} → ${load.destination}`
        };

        this.bidModalError = undefined;
this.bidModalMessage = undefined;
this.assignmentCompleted = false;
this.showBidModal = true;
    }

    async closeBidModal() {
    if (this.assigningBid) {
        return;
    }

    const shouldRefresh =
        this.assignmentCompleted;

    this.showBidModal = false;
    this.selectedBid = undefined;
    this.bidModalError = undefined;
    this.bidModalMessage = undefined;
    this.assignmentCompleted = false;


    if (shouldRefresh) {
        await this.loadBoardData();
    }
}

    async handleAssignBid() {
    if (this.disableAssignBid) {
        return;
    }

    this.assigningBid = true;
    this.bidModalError = undefined;
    this.bidModalMessage = undefined;
    this.successMessage = undefined;

    try {
        const result =
            await assignBid({
                loadId:
                    this.selectedBid.loadId,

                bidId:
                    this.selectedBid.bidId
            });

        if (!result?.success) {
            this.bidModalError =
                result?.message ||
                'The carrier could not be assigned.';

            return;
        }

        /*
         * Keep the popup open so the user can see the result.
         */
        this.assignmentCompleted = true;

        this.bidModalMessage =
            `${result.message} You can click Close.`;

    } catch (error) {
        this.bidModalError =
            this.reduceError(error);

    } finally {
        this.assigningBid = false;
    }
}

    closeDetailsModal() {
        this.showDetailsModal = false;
        this.selectedLoad = undefined;
    }

    handleSearchChange(event) {
        this.searchText =
            event.detail.value;
    }

    decorateLoad(load) {
        if (!load) {
            return {};
        }

        const trailers = [
            load.trailerType,
            load.requiredTrailer
        ].filter(Boolean);

        const totalMiles =
            load.totalMiles != null
                ? load.totalMiles
                : load.distance;

        const bids =
            Array.isArray(load.bids)
                ? load.bids.map((bid) => ({
                    ...bid,

                    contactDisplay:
                        bid.contactName ||
                        'Not provided',

                    emailDisplay:
                        bid.email ||
                        'Not provided',

                    phoneDisplay:
                        bid.phone ||
                        'Not provided',

                    ratingDisplay:
                        bid.rating ||
                        'Not rated',

                    rateDisplay:
                        this.formatCurrency(
                            bid.rate
                        ),

                    transitionDateDisplay:
                        this.formatDateTime(
                            bid.transitionDate
                        ),

                    transitTimeDisplay:
                        bid.transitTime
                            ? `${bid.transitTime}`
                            : 'Not provided',

                    submittedDateDisplay:
                        this.formatDateTime(
                            bid.submittedDate
                        )
                }))
                : [];

        return {
            ...load,

            pickupDateFormatted:
                this.formatDate(
                    load.pickupDate
                ),

            deliveryDateFormatted:
                this.formatDate(
                    load.deliveryDate
                ),

            trailerDisplay:
                trailers.length
                    ? trailers.join(' / ')
                    : 'Equipment not specified',

            weightFormatted:
                this.formatNumberWithUnit(
                    load.weight,
                    'lb'
                ),

            milesFormatted:
                this.formatNumberWithUnit(
                    totalMiles,
                    'mi'
                ),

            palletsFormatted:
                this.formatNumber(
                    load.palletCount
                ),

            commodityDisplay:
                load.commodity ||
                'General Freight',

            hazmatDisplay:
                load.hazmat
                    ? 'Yes'
                    : 'No',

            temperatureFormatted:
                load.temperature == null
                    ? '—'
                    : `${load.temperature}°`,

            sizeDisplay:
                load.size || '—',

            loadStatus:
                load.loadStatus || 'Open',

            totalRateDisplay:
                this.formatCurrency(
                    load.totalRateToCarrier
                ),

            bids,

            hasBids:
                bids.length > 0
        };
    }

    formatDate(value) {
        if (!value) {
            return 'Date not provided';
        }

        const match =
            /^(\d{4})-(\d{2})-(\d{2})$/
                .exec(String(value));

        const dateValue = match
            ? new Date(
                Number(match[1]),
                Number(match[2]) - 1,
                Number(match[3])
            )
            : new Date(value);

        if (Number.isNaN(dateValue.getTime())) {
            return 'Date not provided';
        }

        return new Intl.DateTimeFormat(
            'en-US',
            {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
            }
        ).format(dateValue);
    }

    formatDateTime(value) {
        if (!value) {
            return 'Not provided';
        }

        const dateValue =
            new Date(value);

        if (Number.isNaN(dateValue.getTime())) {
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

    formatNumber(value) {
        if (value == null || value === '') {
            return '—';
        }

        return new Intl.NumberFormat(
            'en-US',
            {
                maximumFractionDigits: 0
            }
        ).format(Number(value));
    }

    formatNumberWithUnit(
        value,
        unit
    ) {
        const formatted =
            this.formatNumber(value);

        return formatted === '—'
            ? formatted
            : `${formatted} ${unit}`;
    }

    formatCurrency(value) {
        if (value == null || value === '') {
            return '—';
        }

        return new Intl.NumberFormat(
            'en-US',
            {
                style: 'currency',
                currency: 'USD',
                maximumFractionDigits: 2
            }
        ).format(Number(value));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .filter(Boolean)
                .join(', ');
        }

        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.'
        );
    }
}

/*sf project deploy start `
    --source-dir "force-app/main/default/lwc/carrierLoadBoard" `
    --target-org "CarrierLoadBoardProduction" `
    --wait 30
    */