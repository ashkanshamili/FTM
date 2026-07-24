import { LightningElement, track } from 'lwc';
import FTM_LOGO from '@salesforce/resourceUrl/FTM_Logo';

import getPortalData from '@salesforce/apex/DriverLoadPortalController.getPortalData';
import updateLoadStatus from '@salesforce/apex/DriverLoadPortalController.updateLoadStatus';
import saveLocation from '@salesforce/apex/DriverLoadPortalController.saveLocation';
import saveSignature from '@salesforce/apex/DriverLoadPortalController.saveSignature';
import uploadFile from '@salesforce/apex/DriverLoadPortalController.uploadFile';
import recordPortalOpened from '@salesforce/apex/DriverLoadPortalController.recordPortalOpened';
import reportIssue from '@salesforce/apex/DriverLoadPortalController.reportIssue';

export default class DriverLoadPortal extends LightningElement {
    ftmLogoUrl = FTM_LOGO;

    get brandTitle() {
        const driverName = this.data?.driverName?.trim();

        return driverName || 'Driver Portal';
    }
    token;

    @track data;
    @track error;

    loading = true;
    actionInProgress = false;
    actionMessage = '';

    activeTab = 'loadDetails';

    trackingMessage = '';
    watchId;
    lastLocationSentAt = 0;
    minLocationFrequencyMs = 30 * 60 * 1000;

    canvasInitialized = false;
    drawing = false;
    signatureMessage = '';
    signatureSaving = false;
    signerName = '';
    signatureType = 'Driver';
    hasSignatureDrawing = false;

    selectedFile;
    selectedFileBase64;
    fileMessage = '';
    fileUploading = false;

    issueType = '';
    issueNotes = '';
    issueMessage = '';
    issueSubmitting = false;

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);

        this.token = params.get('t') || params.get('token');

        if (!this.token) {
            this.error = 'Missing portal token.';
            this.loading = false;
            return;
        }

        this.recordOpen();
        this.loadPortal();
    }

    renderedCallback() {
        if (
            !this.isSignatureTab ||
            !this.data ||
            this.canvasInitialized
        ) {
            return;
        }

        const canvas =
            this.template.querySelector('canvas.signature-canvas');

        if (!canvas) {
            return;
        }

        this.initializeCanvas(canvas);
        this.canvasInitialized = true;
    }

    goToLoadDetails() {
        this.activeTab = 'loadDetails';
    }

    goToReportIssue() {
        this.activeTab = 'reportIssue';
    }

    goToUploadPod() {
        this.activeTab = 'uploadPod';
    }

    goToSignature() {
        this.activeTab = 'signature';
        this.signatureType = this.signatureSignerType;
        this.canvasInitialized = false;
        this.hasSignatureDrawing = false;
        this.signatureMessage = '';
    }

    goToUpdateStatus() {
        if (
            this.isStatusOneOf([
                'assigned',
                'dispatched',
                'in transit to pickup',
                'at shipping'
            ])
        ) {
            this.activeTab = 'pickup';
            return;
        }

        this.activeTab = 'delivery';
    }

    get isLoadDetailsTab() {
        return this.activeTab === 'loadDetails';
    }

    get isPickupTab() {
        return this.activeTab === 'pickup';
    }

    get isDeliveryTab() {
        return this.activeTab === 'delivery';
    }

    get isReportIssueTab() {
        return this.activeTab === 'reportIssue';
    }

    get isUploadPodTab() {
        return this.activeTab === 'uploadPod';
    }

    get isSignatureTab() {
        return this.activeTab === 'signature';
    }

    get normalizedStatus() {
        return this.normalizeStatus(this.data?.status);
    }

    normalizeStatus(value) {
        return value
            ? value.toString().trim().toLowerCase()
            : '';
    }

    isStatusOneOf(statuses) {
        return statuses.includes(this.normalizedStatus);
    }

    get arrivedPickupDisabled() {
        return (
            this.actionInProgress ||
            !this.isStatusOneOf([
                'assigned',
                'in transit to pickup',
                'dispatched'
            ])
        );
    }

    get departedPickupDisabled() {
        return (
            this.actionInProgress ||
            !this.isStatusOneOf([
                'at shipping',
                'arrived for pickup'
            ])
        );
    }

    get arrivedDeliveryDisabled() {
        return (
            this.actionInProgress ||
            !this.isStatusOneOf([
                'in transit to delivery',
                'departed pickup'
            ])
        );
    }

    get deliveredDisabled() {
        return (
            this.actionInProgress ||
            !this.isStatusOneOf([
                'at receiving',
                'arrived for delivery'
            ])
        );
    }

    get hasLegs() {
        return (
            this.data &&
            this.data.legs &&
            this.data.legs.length > 0
        );
    }

    get fileUploadDisabled() {
        return (
            this.fileUploading ||
            !this.selectedFile ||
            !this.selectedFileBase64
        );
    }

    get displayRoute() {
        return this.valueOrDash(this.data?.route);
    }

    get displayDriverName() {
        return this.valueOrDash(this.data?.driverName);
    }

    get displayDriverEmail() {
        return this.valueOrDash(this.data?.driverEmail);
    }

    get displayCarrierName() {
        return this.valueOrDash(this.data?.carrierName);
    }

    get displayCarrierEmail() {
        return this.valueOrDash(this.data?.carrierEmail);
    }

    get displayPickupFacility() {
        return this.valueOrDash(this.data?.pickupFacility);
    }

    get displayPickupAddress() {
        return this.valueOrDash(this.data?.pickupAddress);
    }

    get displayPickupContact() {
        return this.valueOrDash(this.data?.pickupContact);
    }

    get displayPickupPhone() {
        return this.valueOrDash(this.data?.pickupPhone);
    }

    get displayPickupEmail() {
        return this.valueOrDash(this.data?.pickupEmail);
    }

    get displayPickupRef() {
        return this.valueOrDash(this.data?.pickupRef);
    }

    get displayPickupRemarks() {
        return this.valueOrDash(this.data?.pickupRemarks);
    }

    get displayDeliveryFacility() {
        return this.valueOrDash(this.data?.deliveryFacility);
    }

    get displayDeliveryAddress() {
        return this.valueOrDash(this.data?.deliveryAddress);
    }

    get displayDeliveryContact() {
        return this.valueOrDash(this.data?.deliveryContact);
    }

    get displayDeliveryPhone() {
        return this.valueOrDash(this.data?.deliveryPhone);
    }

    get displayDeliveryEmail() {
        return this.valueOrDash(this.data?.deliveryEmail);
    }

    get displayDeliveryRef() {
        return this.valueOrDash(this.data?.deliveryRef);
    }

    get displayDeliveryRemarks() {
        return this.valueOrDash(this.data?.deliveryRemarks);
    }

    get displayCommodity() {
        return this.valueOrDash(this.data?.commodity);
    }

    get displayWeight() {
        return this.valueOrDash(this.data?.weight);
    }

    get displayDistance() {
        return this.valueOrDash(this.data?.distance);
    }

    get displayRequirements() {
        return this.valueOrDash(this.data?.requirements);
    }

    get displayRemarks() {
        return this.valueOrDash(this.data?.remarks);
    }

    get displayDriverRemarks() {
        return this.valueOrDash(this.data?.driverRemarks);
    }

    get displayExceptionReason() {
        return this.valueOrDash(this.data?.exceptionReason);
    }

    get hasReachedPickupArrival() {
        return this.isStatusOneOf([
            'at shipping',
            'arrived for pickup',
            'departed pickup',
            'in transit to delivery',
            'at receiving',
            'arrived for delivery',
            'delivered'
        ]);
    }

    get hasReachedPickupDeparture() {
        return this.isStatusOneOf([
            'departed pickup',
            'in transit to delivery',
            'at receiving',
            'arrived for delivery',
            'delivered'
        ]);
    }

    get hasReachedDeliveryArrival() {
        return this.isStatusOneOf([
            'at receiving',
            'arrived for delivery',
            'delivered'
        ]);
    }

    get hasReachedDeliveryDeparture() {
        return this.isStatusOneOf([
            'delivered'
        ]);
    }

    get pickupArrivalText() {
        return this.hasReachedPickupArrival
            ? this.formatDateTime(this.data?.pickupArrival)
            : '—';
    }

    get pickupDepartureText() {
        return this.hasReachedPickupDeparture
            ? this.formatDateTime(this.data?.pickupDeparture)
            : '—';
    }

    get deliveryArrivalText() {
        return this.hasReachedDeliveryArrival
            ? this.formatDateTime(this.data?.deliveryArrival)
            : '—';
    }

    get deliveryDepartureText() {
        return this.hasReachedDeliveryDeparture
            ? this.formatDateTime(this.data?.deliveryDeparture)
            : '—';
    }

    get pickupArrivalDotClass() {
        return (
            this.hasReachedPickupArrival &&
            this.data?.pickupArrival
        )
            ? 'activity-dot complete'
            : 'activity-dot pending';
    }

    get pickupDepartureDotClass() {
        return (
            this.hasReachedPickupDeparture &&
            this.data?.pickupDeparture
        )
            ? 'activity-dot complete'
            : 'activity-dot pending';
    }

    get deliveryArrivalDotClass() {
        return (
            this.hasReachedDeliveryArrival &&
            this.data?.deliveryArrival
        )
            ? 'activity-dot complete'
            : 'activity-dot pending';
    }

    get deliveryDepartureDotClass() {
        return (
            this.hasReachedDeliveryDeparture &&
            this.data?.deliveryDeparture
        )
            ? 'activity-dot complete'
            : 'activity-dot pending';
    }

    get isPickupSignatureStatus() {
        return this.isStatusOneOf([
            'assigned',
            'dispatched',
            'in transit to pickup',
            'at shipping',
            'arrived for pickup'
        ]);
    }

    get signaturePageTitle() {
        return this.isPickupSignatureStatus
            ? 'Pickup Signature'
            : 'Delivery Signature';
    }

    get signatureSignerType() {
        return this.isPickupSignatureStatus
            ? 'Pickup Contact'
            : 'Delivery Contact';
    }

    get issueCharacterCount() {
        return this.issueNotes
            ? this.issueNotes.length
            : 0;
    }

    valueOrDash(value) {
        return (
            value === null ||
            value === undefined ||
            value === ''
        )
            ? '-'
            : value;
    }

    formatDateTime(value) {
        if (!value) {
            return '—';
        }

        const dateValue = new Date(value);

        if (Number.isNaN(dateValue.getTime())) {
            return '—';
        }

        return new Intl.DateTimeFormat(undefined, {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(dateValue);
    }

    async loadPortal() {
        try {
            this.loading = true;
            this.error = null;

            this.data = await getPortalData({
                token: this.token
            });
        } catch (error) {
            this.error = this.normalizeError(error);
        } finally {
            this.loading = false;
        }
    }

    async recordOpen() {
        try {
            await recordPortalOpened({
                token: this.token
            });
        } catch (error) {
            console.error(
                'Unable to record portal open',
                error
            );
        }
    }

    async handleStatusClick(event) {
        const actionName =
            event.currentTarget?.dataset?.action ||
            event.target?.dataset?.action;

        if (!actionName) {
            return;
        }

        try {
            this.actionInProgress = true;
            this.error = null;
            this.actionMessage =
                'Capturing location and submitting update...';

            const position =
                await this.getCurrentBrowserLocation();

            if (position) {
                await this.saveActionLocation(
                    position,
                    actionName
                );
            }

            await updateLoadStatus({
                token: this.token,
                actionName
            });

            if (actionName === 'DELIVERED') {
                this.actionMessage = position
                    ? 'Delivery completed and location saved.'
                    : 'Delivery completed. Location was not available or permission was denied.';

                this.data = {
                    ...this.data,
                    status: 'Delivered',
                    portalClosed: true,
                    portalClosedMessage:
                        'This delivery has been completed. Thank you.'
                };

                return;
            }

            this.actionMessage = position
                ? 'Status updated and location saved.'
                : 'Status updated. Location was not available or permission was denied.';

            await this.sleep(2000);
            await this.loadPortal();
            this.goToLoadDetails();
        } catch (error) {
            this.error = this.normalizeError(error);
            this.actionMessage = this.error;
        } finally {
            this.actionInProgress = false;
        }
    }

    getCurrentBrowserLocation() {
        return new Promise(resolve => {
            if (!navigator.geolocation) {
                resolve(null);
                return;
            }

            navigator.geolocation.getCurrentPosition(
                position => {
                    resolve(position);
                },
                () => {
                    resolve(null);
                },
                {
                    enableHighAccuracy: true,
                    timeout: 15000,
                    maximumAge: 60000
                }
            );
        });
    }

    async saveActionLocation(
        position,
        actionName
    ) {
        if (!position || !position.coords) {
            return;
        }

        const deviceInfo =
            `${navigator.platform || ''} ` +
            `${navigator.userAgent || ''} ` +
            `| Action: ${actionName}`;

        await saveLocation({
            token: this.token,
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            deviceInfo: deviceInfo.substring(0, 250)
        });
    }

    startTracking() {
        if (!navigator.geolocation) {
            this.trackingMessage =
                'Geolocation is not supported by this browser.';
            return;
        }

        this.trackingMessage =
            'Requesting location permission...';

        this.watchId =
            navigator.geolocation.watchPosition(
                position =>
                    this.handlePosition(position),
                error =>
                    this.handleLocationError(error),
                {
                    enableHighAccuracy: true,
                    timeout: 15000,
                    maximumAge: 60000
                }
            );
    }

    async handlePosition(position) {
        const now = Date.now();

        if (
            now - this.lastLocationSentAt <
            this.minLocationFrequencyMs
        ) {
            this.trackingMessage =
                'Location tracking is active.';
            return;
        }

        this.lastLocationSentAt = now;

        const deviceInfo =
            `${navigator.platform || ''} ` +
            `${navigator.userAgent || ''}`;

        try {
            await saveLocation({
                token: this.token,
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                deviceInfo:
                    deviceInfo.substring(0, 250)
            });

            this.trackingMessage =
                'Location shared successfully.';
        } catch (error) {
            this.trackingMessage =
                this.normalizeError(error);
        }
    }

    handleLocationError(error) {
        if (
            error.code ===
            error.PERMISSION_DENIED
        ) {
            this.trackingMessage =
                'Location permission was denied.';
        } else if (
            error.code ===
            error.POSITION_UNAVAILABLE
        ) {
            this.trackingMessage =
                'Location is unavailable.';
        } else if (
            error.code ===
            error.TIMEOUT
        ) {
            this.trackingMessage =
                'Location request timed out.';
        } else {
            this.trackingMessage =
                'Unable to get location.';
        }
    }

    initializeCanvas(canvas) {
        const ratio = Math.max(
            window.devicePixelRatio || 1,
            1
        );

        const rect =
            canvas.getBoundingClientRect();

        canvas.width =
            rect.width * ratio;

        canvas.height =
            200 * ratio;

        const context =
            canvas.getContext('2d');

        context.scale(ratio, ratio);
        context.lineWidth = 3;
        context.lineCap = 'round';
        context.lineJoin = 'round';
        context.strokeStyle = '#000000';
        context.fillStyle = '#ffffff';

        context.fillRect(
            0,
            0,
            rect.width,
            200
        );
    }

    handleSignerNameChange(event) {
        this.signerName = event.target.value;
        this.signatureMessage = '';
    }

    handleSignatureTypeChange(event) {
        this.signatureType = event.target.value;
    }

    startDrawing(event) {
        event.preventDefault();

        const canvas =
            this.template.querySelector(
                'canvas.signature-canvas'
            );

        if (!canvas) {
            return;
        }

        const point =
            this.getPoint(event, canvas);

        const context =
            canvas.getContext('2d');

        this.drawing = true;
        this.hasSignatureDrawing = true;
        this.signatureMessage = '';

        context.beginPath();
        context.moveTo(
            point.x,
            point.y
        );
    }

    draw(event) {
        if (!this.drawing) {
            return;
        }

        event.preventDefault();

        const canvas =
            this.template.querySelector(
                'canvas.signature-canvas'
            );

        if (!canvas) {
            return;
        }

        const point =
            this.getPoint(event, canvas);

        const context =
            canvas.getContext('2d');

        context.lineTo(
            point.x,
            point.y
        );

        context.stroke();
    }

    stopDrawing(event) {
        if (event) {
            event.preventDefault();
        }

        this.drawing = false;
    }

    getPoint(event, canvas) {
        const rect =
            canvas.getBoundingClientRect();

        let clientX;
        let clientY;

        if (
            event.touches &&
            event.touches.length > 0
        ) {
            clientX =
                event.touches[0].clientX;

            clientY =
                event.touches[0].clientY;
        } else {
            clientX = event.clientX;
            clientY = event.clientY;
        }

        return {
            x: clientX - rect.left,
            y: clientY - rect.top
        };
    }

    clearSignature() {
        const canvas =
            this.template.querySelector(
                'canvas.signature-canvas'
            );

        if (!canvas) {
            return;
        }

        const context =
            canvas.getContext('2d');

        const rect =
            canvas.getBoundingClientRect();

        context.clearRect(
            0,
            0,
            canvas.width,
            canvas.height
        );

        context.fillStyle = '#ffffff';

        context.fillRect(
            0,
            0,
            rect.width,
            200
        );

        this.hasSignatureDrawing = false;
    }

    async submitSignature() {
        const canvas =
            this.template.querySelector(
                'canvas.signature-canvas'
            );

        if (!canvas) {
            this.signatureMessage =
                'Signature pad is not ready.';
            return;
        }

        if (
            !this.signerName ||
            this.signerName.trim() === ''
        ) {
            this.signatureMessage =
                'Please enter signer name.';
            return;
        }

        if (!this.hasSignatureDrawing) {
            this.signatureMessage =
                'Please enter signature.';
            return;
        }

        const dataUrl =
            canvas.toDataURL('image/png');

        try {
            this.signatureSaving = true;

            this.signatureMessage =
                'Saving signature...';

            await saveSignature({
                token: this.token,
                signatureDataUrl: dataUrl,
                signerName:
                    this.signerName.trim(),
                signatureType:
                    this.signatureSignerType
            });

            this.signatureMessage =
                'Signature has been saved successfully.';

            this.clearSignature();

            await this.sleep(2000);
            await this.loadPortal();

            this.signerName = '';
            this.goToLoadDetails();
        } catch (error) {
            this.signatureMessage =
                this.normalizeError(error);
        } finally {
            this.signatureSaving = false;
        }
    }

    handleFileChange(event) {
    const file = event.target.files?.[0];

    if (!file) {
        this.selectedFile = null;
        this.selectedFileBase64 = null;
        this.fileMessage = '';
        return;
    }

    /*
     * A synchronous Apex call must hold:
     * - the Base64 request string
     * - the decoded Blob
     * - request and ContentVersion data
     *
     * Keep the original file at or below 1 MB.
     */
    const maxSizeBytes = 1 * 1024 * 1024;

    if (file.size > maxSizeBytes) {
        this.fileMessage =
            'File is too large. Maximum size is 1 MB.';

        this.selectedFile = null;
        this.selectedFileBase64 = null;
        event.target.value = '';
        return;
    }

    this.selectedFile = file;
    this.selectedFileBase64 = null;
    this.fileMessage = `Selected file: ${file.name}`;

    const reader = new FileReader();

    reader.onload = () => {
        const result = reader.result;

        if (typeof result !== 'string') {
            this.fileMessage =
                'The selected file could not be processed.';
            this.selectedFile = null;
            this.selectedFileBase64 = null;
            event.target.value = '';
            return;
        }

        /*
         * Additional protection after Base64 conversion.
         * A 1 MB file is approximately 1.4 million Base64 characters.
         */
        const maxDataUrlLength = 1500000;

        if (result.length > maxDataUrlLength) {
            this.fileMessage =
                'File is too large after processing. Maximum size is 1 MB.';

            this.selectedFile = null;
            this.selectedFileBase64 = null;
            event.target.value = '';
            return;
        }

        this.selectedFileBase64 = result;
        this.fileMessage = `Selected file: ${file.name}`;
    };

    reader.onerror = () => {
        this.fileMessage = 'Unable to read file.';
        this.selectedFile = null;
        this.selectedFileBase64 = null;
        event.target.value = '';
    };

    reader.readAsDataURL(file);
}


    async submitFile() {
    if (!this.selectedFile || !this.selectedFileBase64) {
        this.fileMessage = 'Please select a file first.';
        return;
    }

    if (this.selectedFile.size > 1 * 1024 * 1024) {
        this.fileMessage =
            'File is too large. Maximum size is 1 MB.';
        return;
    }

    if (this.selectedFileBase64.length > 1500000) {
        this.fileMessage =
            'File is too large after processing. Maximum size is 1 MB.';
        return;
    }

    try {
        this.fileUploading = true;
        this.fileMessage = 'Uploading file...';

        await uploadFile({
            token: this.token,
            fileName: this.selectedFile.name,
            base64Data: this.selectedFileBase64
        });

        this.fileMessage = 'File uploaded successfully.';
        this.selectedFile = null;
        this.selectedFileBase64 = null;

        /*
         * Your page can contain more than one file input.
         * Clear all file inputs rather than only the first one.
         */
        const fileInputs =
            this.template.querySelectorAll('input[type="file"]');

        fileInputs.forEach(input => {
            input.value = '';
        });
    } catch (error) {
        this.fileMessage = this.normalizeError(error);
    } finally {
        this.fileUploading = false;
    }
}

    handleIssueTypeChange(event) {
        this.issueType =
            event.target.value;

        this.issueMessage = '';
    }

    handleIssueNotesChange(event) {
        this.issueNotes =
            event.target.value;

        this.issueMessage = '';
    }

    async submitIssue() {
        if (!this.issueType) {
            this.issueMessage =
                'Please select an exception reason.';
            return;
        }

        if (
            !this.issueNotes ||
            this.issueNotes.trim() === ''
        ) {
            this.issueMessage =
                'Please enter driver remarks.';
            return;
        }

        if (
            this.issueNotes.length > 255
        ) {
            this.issueMessage =
                'Driver remarks must be 255 characters or fewer.';
            return;
        }

        try {
            this.issueSubmitting = true;

            this.issueMessage =
                'Submitting issue...';

            await reportIssue({
                token: this.token,
                issueType: this.issueType,
                notes:
                    this.issueNotes.trim()
            });

            this.issueMessage =
                'Issue reported successfully.';

            this.issueType = '';
            this.issueNotes = '';

            const issueTypeInput =
                this.template.querySelector(
                    '#issueType'
                );

            const issueNotesInput =
                this.template.querySelector(
                    '#issueNotes'
                );

            if (issueTypeInput) {
                issueTypeInput.value = '';
            }

            if (issueNotesInput) {
                issueNotesInput.value = '';
            }

            await this.sleep(2000);
            await this.loadPortal();
           // this.goToLoadDetails();
        } catch (error) {
            this.issueMessage =
                this.normalizeError(error);
        } finally {
            this.issueSubmitting = false;
        }
    }

    normalizeError(error) {
        console.error(
            'Driver portal error:',
            error
        );

        if (Array.isArray(error?.body)) {
            return error.body
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error?.body?.message) {
            return error.body.message;
        }

        if (
            error?.body?.pageErrors?.length
        ) {
            return error.body.pageErrors
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (
            error?.body?.fieldErrors
        ) {
            const messages = [];

            Object.values(
                error.body.fieldErrors
            ).forEach(fieldErrors => {
                fieldErrors.forEach(
                    fieldError => {
                        if (fieldError.message) {
                            messages.push(
                                fieldError.message
                            );
                        }
                    }
                );
            });

            if (messages.length > 0) {
                return messages.join(', ');
            }
        }

        if (error?.message) {
            return error.message;
        }

        return 'Something went wrong.';
    }

    sleep(milliseconds) {
        return new Promise(resolve => {
            window.setTimeout(
                resolve,
                milliseconds
            );
        });
    }
}