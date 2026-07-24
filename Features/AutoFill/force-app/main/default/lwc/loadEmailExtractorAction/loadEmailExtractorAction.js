import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LightningElement } from 'lwc';

import approveAutoFillLoad from '@salesforce/apex/AutoFillController.approveAutoFillLoad';
import getDraftAutoFillLoads from '@salesforce/apex/AutoFillController.getDraftAutoFillLoads';
import getExtractedDocument from '@salesforce/apex/AutoFillController.getExtractedDocument';
import getExtractedItems from '@salesforce/apex/AutoFillController.getExtractedItems';
import getLoadFilePreviews from '@salesforce/apex/AutoFillController.getLoadFilePreviews';
import rejectAutoFillLoad from '@salesforce/apex/AutoFillController.rejectAutoFillLoad';
import sendEmailContent from '@salesforce/apex/AutoFillController.sendEmailContent';

const MAX_FILE_BYTES = 4500000;
const IMAGE_FILE_TYPES = new Set([
    'BMP',
    'GIF',
    'JFIF',
    'JPEG',
    'JPG',
    'PNG',
    'TIF',
    'TIFF',
    'WEBP'
]);
const LOAD_OBJECT_API_NAME = 'FreightTM__Load__c';
const AUTOFILL_STATUS_DIRECT = 'Direct';
const AUTOFILL_STATUS_DRAFT = 'Draft';
const AUTOFILL_STATUS_APPROVED = 'Approved';
const AUTOFILL_STATUS_REJECTED = 'Rejected';

export default class AutoFillWorkspace extends NavigationMixin(LightningElement) {
    isSending = false;
    isLoadingExtract = false;
    isApproving = false;
    isRejecting = false;
    isLoadingDraftLoads = false;
    draftLoads = [];
    draftLoadsErrorMessage = '';
    draftLoadsPage = 1;
    draftLoadsPageSize = 10;
    draftLoadsTotal = 0;
    draftLoadsTotalPages = 1;
    draftLoadsSearchInput = '';
    draftLoadsSearchTerm = '';
    activeDraftLoadId = '';
    pendingApproveDraftLoadId = '';
    pendingRejectDraftLoadId = '';
    showApproveDraftModal = false;
    showRejectDraftModal = false;
    showDetectedFieldsModal = false;
    rejectionReason = '';
    detectedFieldsModalRows = [];
    detectedFieldsModalTitle = '';
    detectedFieldsSavedRows = [];
    detectedFieldsNotSavedRows = [];
    detectedFieldsRawRows = [];
    detectedFieldsChildTables = [];
    detectedFieldsSavedCountLabel = '0';
    detectedFieldsNotSavedCountLabel = '0';
    detectedFieldsRawCountLabel = '0';
    detectedFieldsFiles = [];
    detectedSourceText = '';
    selectedDetectedFileId = '';
    isLoadingDetectedFilePreview = false;
    detectedFilePreviewError = '';
    detectedPreviewLoadTimer;
    showRawJsonModal = false;
    rawJsonModalTitle = '';
    rawJsonText = '';

    emailContent = '';
    files = [];
    selectedFileNames = [];

    errorMessage = '';
    successMessage = '';
    extractErrorMessage = '';

    createdRecordId = '';
    createdObjectType = '';
    createdRecordDeleted = false;

    itemId = '';
    autoFillStatus = '';
    documentStatus = '';
    webhookStatus = '';
    detectedDocumentType = '';
    documentConfidence = '';
    classificationConfidence = '';
    autoFillSource = '';
    autoFillFieldCount = '';
    autoFillAllFieldsDetected = null;
    failureReason = '';
    processedAt = '';
    extractRows = [];
    uploadRawJson = '';

    extractedItemsRows = [];
    extractedItemsPage = 1;
    extractedItemsPageSize = 20;
    extractedItemsTotal = 0;
    isLoadingExtractedItems = false;
    extractedItemsErrorMessage = '';

    hasLoadedExtractedItemsOnInit = false;

    connectedCallback() {
        this.loadExtractedItemsOnInit();
        this.loadDraftLoads();
    }

    disconnectedCallback() {
        this.clearDetectedPreviewTimer();
    }

    async loadExtractedItemsOnInit() {
        if (this.hasLoadedExtractedItemsOnInit) {
            return;
        }

        this.hasLoadedExtractedItemsOnInit = true;
        await this.loadExtractedItems();
    }

    get sendButtonLabel() {
        return this.isSending ? 'Processing...' : 'Send to AutoFill';
    }

    get hasSelectedFiles() {
        return this.selectedFileNames.length > 0;
    }

    get hasCreatedRecord() {
        return Boolean(this.createdRecordId);
    }

    get hasViewableCreatedRecord() {
        return Boolean(this.createdRecordId) && !this.createdRecordDeleted;
    }

    get isLoadRecord() {
        return this.createdObjectType === LOAD_OBJECT_API_NAME;
    }

    get createdObjectTypeLabel() {
        return this.isLoadRecord ? 'Load' : this.createdObjectType;
    }

    get showAutoFillReview() {
        return this.hasCreatedRecord && this.isLoadRecord;
    }

    get canApproveReject() {
        return (
            this.showAutoFillReview &&
            this.isDraftStatus(this.autoFillStatus) &&
            !this.createdRecordDeleted &&
            !this.isApproving &&
            !this.isRejecting
        );
    }

    get approveButtonDisabled() {
        return !this.canApproveReject;
    }

    get rejectButtonDisabled() {
        return !this.canApproveReject;
    }

    get hasExtractRows() {
        return this.extractRows && this.extractRows.length > 0;
    }

    get hasDocumentMeta() {
        return Boolean(
            this.documentStatus ||
            this.webhookStatus ||
            this.detectedDocumentType ||
            this.processedAt ||
            this.failureReason
        );
    }

    get showExtractSection() {
        return (
            this.hasExtractRows ||
            this.isLoadingExtract ||
            Boolean(this.extractErrorMessage) ||
            Boolean(this.itemId) ||
            Boolean(this.detectedDocumentType) ||
            Boolean(this.documentConfidence) ||
            Boolean(this.classificationConfidence)
        );
    }

    get disableSendButton() {
        return this.isSending || this.isApproving || this.isRejecting;
    }

    get formattedConfidence() {
        if (this.documentConfidence === null || this.documentConfidence === undefined || this.documentConfidence === '') {
            return '';
        }

        const numericConfidence = Number(this.documentConfidence);

        if (Number.isNaN(numericConfidence)) {
            return String(this.documentConfidence);
        }

        return numericConfidence <= 1
            ? `${Math.round(numericConfidence * 100)}% confidence`
            : `${Math.round(numericConfidence)}% confidence`;
    }


    get formattedClassificationConfidence() {
        const formattedValue = this.formatConfidenceValue(this.classificationConfidence);
        return formattedValue ? `${formattedValue} classification confidence` : '';
    }

    get autoFillStatusClass() {
        const base = 'status-pill';

        if (this.autoFillStatus === AUTOFILL_STATUS_APPROVED) {
            return `${base} approved`;
        }

        if (this.autoFillStatus === AUTOFILL_STATUS_REJECTED) {
            return `${base} rejected`;
        }

        if (this.isDraftStatus(this.autoFillStatus)) {
            return `${base} direct`;
        }

        return `${base} default`;
    }

    get hasExtractedItemsRows() {
    return this.extractedItemsRows && this.extractedItemsRows.length > 0;
}

get showExtractedItemsSection() {
    return (
        this.hasExtractedItemsRows ||
        this.isLoadingExtractedItems ||
        Boolean(this.extractedItemsErrorMessage)
    );
}

get disableExtractedItemsPrevious() {
    return this.extractedItemsPage <= 1 || this.isLoadingExtractedItems;
}

get disableExtractedItemsNext() {
    return (
        this.isLoadingExtractedItems ||
        this.extractedItemsPage * this.extractedItemsPageSize >= this.extractedItemsTotal
    );
}

get extractedItemsMetaLabel() {
    return `Page ${this.extractedItemsPage} · ${this.extractedItemsTotal} total`;
}


get hasDraftLoads() {
    return this.draftLoads && this.draftLoads.length > 0;
}

get draftLoadsMetaLabel() {
    const count = this.draftLoadsTotal || 0;

    if (this.draftLoadsSearchTerm) {
        return `${count} matching draft ${count === 1 ? 'item' : 'items'}`;
    }

    return `${count} draft ${count === 1 ? 'item' : 'items'}`;
}

get draftLoadsPageLabel() {
    const totalPages = Math.max(this.draftLoadsTotalPages || 1, 1);
    return `Page ${this.draftLoadsPage} of ${totalPages}`;
}

get disableDraftLoadsPrevious() {
    return this.draftLoadsPage <= 1 || this.isLoadingDraftLoads;
}

get disableDraftLoadsNext() {
    return (
        this.isLoadingDraftLoads ||
        this.draftLoadsPage >= Math.max(this.draftLoadsTotalPages || 1, 1)
    );
}

get disableDraftLoadsClear() {
    return (
        this.isLoadingDraftLoads ||
        (!this.draftLoadsSearchInput && !this.draftLoadsSearchTerm)
    );
}

get draftLoadsEmptyMessage() {
    return this.draftLoadsSearchTerm
        ? 'No draft AutoFill loads match this load or route search.'
        : 'No draft AutoFill loads are waiting for review.';
}

get disableDraftActions() {
    return this.isLoadingDraftLoads || this.isApproving || this.isRejecting;
}

get selectedDraftLoad() {
    const selectedId = this.pendingApproveDraftLoadId || this.pendingRejectDraftLoadId;
    return (this.draftLoads || []).find((load) => load.id === selectedId);
}

get selectedReviewLoad() {
    const draftLoad = this.selectedDraftLoad;

    if (draftLoad) {
        return draftLoad;
    }

    const selectedId = this.pendingApproveDraftLoadId || this.pendingRejectDraftLoadId;

    if (selectedId && selectedId === this.createdRecordId) {
        return {
            loadName: this.createdRecordId,
            fieldCountLabel: this.autoFillFieldCount === null || this.autoFillFieldCount === undefined || this.autoFillFieldCount === '' ? '0' : String(this.autoFillFieldCount),
            savedFieldCountLabel: this.autoFillFieldCount === null || this.autoFillFieldCount === undefined || this.autoFillFieldCount === '' ? '0' : String(this.autoFillFieldCount),
            notSavedFieldCountLabel: 'Open Fields to review',
            confidenceLabel: this.formatConfidenceValue(this.documentConfidence) || 'Not available',
            classificationConfidenceLabel: this.formatConfidenceValue(this.classificationConfidence) || 'Not available',
            sourceLabel: this.normalizeSourceLabel(this.autoFillSource) || 'Manual Upload',
            documentTypeLabel: this.detectedDocumentType || 'Not available'
        };
    }

    return null;
}

get hasDetectedFieldsModalRows() {
    return (
        (this.detectedFieldsModalRows && this.detectedFieldsModalRows.length > 0) ||
        this.hasDetectedFieldsChildTables
    );
}

get hasDetectedFieldsSavedRows() {
    return this.detectedFieldsSavedRows && this.detectedFieldsSavedRows.length > 0;
}

get hasDetectedFieldsNotSavedRows() {
    return this.detectedFieldsNotSavedRows && this.detectedFieldsNotSavedRows.length > 0;
}

get hasDetectedFieldsRawRows() {
    return this.detectedFieldsRawRows && this.detectedFieldsRawRows.length > 0;
}

get hasDetectedFieldsChildTables() {
    return this.detectedFieldsChildTables && this.detectedFieldsChildTables.length > 0;
}

get hasDetectedFieldsFiles() {
    return this.detectedFieldsFiles && this.detectedFieldsFiles.length > 0;
}

get hasDetectedSourceText() {
    return Boolean(String(this.detectedSourceText || '').trim());
}

get hasDetectedInlinePreviewFiles() {
    return (this.detectedFieldsFiles || []).some(
        (file) => file.canInlinePreview
    );
}

get showDetectedSourceTextPreview() {
    return (
        !this.isLoadingDetectedFilePreview &&
        !this.detectedFilePreviewError &&
        !this.hasDetectedInlinePreviewFiles &&
        this.hasDetectedSourceText
    );
}

get showUnsupportedDetectedFilePreview() {
    return (
        !this.isLoadingDetectedFilePreview &&
        !this.detectedFilePreviewError &&
        this.hasSelectedDetectedFile &&
        !this.selectedDetectedFileCanInlinePreview &&
        !this.showDetectedSourceTextPreview
    );
}

get selectedDetectedFile() {
    return (this.detectedFieldsFiles || []).find(
        (file) => file.contentDocumentId === this.selectedDetectedFileId
    ) || null;
}

get hasSelectedDetectedFile() {
    return Boolean(this.selectedDetectedFile);
}

get selectedDetectedFileIsPdf() {
    return Boolean(this.selectedDetectedFile?.isPdf);
}

get selectedDetectedFileIsImage() {
    return Boolean(this.selectedDetectedFile?.isImage);
}

get selectedDetectedFileCanInlinePreview() {
    return Boolean(this.selectedDetectedFile?.canInlinePreview);
}

get selectedDetectedFileTitle() {
    return this.selectedDetectedFile?.title || 'Uploaded file';
}

get selectedDetectedFilePreviewUrl() {
    return this.selectedDetectedFile?.previewUrl || '';
}

get selectedDetectedFilePreviewHeading() {
    if (!this.hasDetectedInlinePreviewFiles && this.hasDetectedSourceText) {
        return 'Text preview';
    }

    if (this.selectedDetectedFileIsPdf) {
        return 'PDF preview';
    }

    if (this.selectedDetectedFileIsImage) {
        return 'Image preview';
    }

    return 'File preview';
}

get selectedDetectedFileLoadingText() {
    return this.selectedDetectedFileIsImage
        ? 'Loading the attached image preview…'
        : 'Loading the attached PDF preview…';
}

get showNoDetectedFilePreview() {
    return (
        !this.isLoadingDetectedFilePreview &&
        !this.detectedFilePreviewError &&
        !this.hasDetectedFieldsFiles &&
        !this.hasDetectedSourceText
    );
}

get hasUploadRawJson() {
    return Boolean(this.uploadRawJson);
}

get hasRawJsonText() {
    return Boolean(this.rawJsonText);
}


    async loadDraftLoads() {
        this.isLoadingDraftLoads = true;
        this.draftLoadsErrorMessage = '';

        try {
            const result = await getDraftAutoFillLoads({
                pageNumber: this.draftLoadsPage,
                pageSize: this.draftLoadsPageSize,
                searchTerm: this.draftLoadsSearchTerm
            });

            this.draftLoadsPage = result?.page || this.draftLoadsPage;
            this.draftLoadsPageSize = result?.pageSize || this.draftLoadsPageSize;
            this.draftLoadsTotal = result?.total || 0;
            this.draftLoadsTotalPages = result?.totalPages || 1;

            const rows = result?.items || [];
            this.draftLoads = rows.map((row) => {
                const displayStatus = this.isDraftStatus(row.autoFillStatus) ? 'Draft' : (row.autoFillStatus || 'Draft');
                const detectedAudit = this.parseDetectedFieldsAudit(row.detectedFieldsJson);
                const childTables = this.parseV2ChildTables(row.rawResponseJson);
                const savedCount = detectedAudit.savedRows.length;
                const notSavedCount = detectedAudit.notSavedRows.length;
                const rawCount = detectedAudit.rawRows.length;

                return {
                    ...row,
                    id: row.loadId,
                    displayStatus,
                    statusClass: this.getStatusPillClass(displayStatus),
                    createdDateLabel: this.formatDateTime(row.createdDate),
                    amountLabel: this.formatCurrency(row.totalAmount),
                    confidenceLabel: this.formatConfidenceValue(row.confidence) || 'Not available',
                    routeLabel: row.route || 'Route not available',
                    sourceLabel: this.resolveDraftSourceLabel(row),
                    sourceIcon: this.getSourceIcon(row),
                    sourceClass: this.getSourceClass(row),
                    classificationConfidence: row.classificationConfidence ?? row.confidence ?? '',
                    classificationConfidenceLabel: this.formatConfidenceValue(
                        row.classificationConfidence ?? row.confidence
                    ) || 'Not available',
                    documentTypeLabel: row.documentType || 'Not available',
                    fieldCountLabel: detectedAudit.isStructured
                        ? String(savedCount)
                        : (row.fieldCount === null || row.fieldCount === undefined ? 'Not available' : String(row.fieldCount)),
                    savedFieldCountLabel: detectedAudit.isStructured ? String(savedCount) : 'Not available',
                    notSavedFieldCountLabel: detectedAudit.isStructured ? String(notSavedCount) : 'Not available',
                    rawDetectedFieldCountLabel: rawCount ? String(rawCount) : '0',
                    allFieldsDetectedLabel: row.allFieldsDetected ? 'Yes' : 'Not confirmed',
                    allFieldsDetectedClass: row.allFieldsDetected ? 'status-pill approved' : 'status-pill default',
                    detectedFieldsRows: detectedAudit.allRows,
                    detectedFieldsSavedRows: detectedAudit.savedRows,
                    detectedFieldsNotSavedRows: detectedAudit.notSavedRows,
                    detectedFieldsRawRows: detectedAudit.rawRows,
                    detectedFieldsChildTables: childTables,
                    rawResponseJson: row.rawResponseJson || '',
                    sourceText:
                        row.sourceText ||
                        this.extractDetectedSourceText(row.rawResponseJson),
                    noRawJson: !row.rawResponseJson,
                    hasDetectedFields: detectedAudit.allRows.length > 0 || childTables.length > 0,
                    noDetectedFields: detectedAudit.allRows.length === 0 && childTables.length === 0
                };
            });
        } catch (error) {
            this.draftLoads = [];
            this.draftLoadsTotal = 0;
            this.draftLoadsTotalPages = 1;
            this.draftLoadsErrorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoadingDraftLoads = false;
        }
    }

    refreshDraftLoads() {
        this.loadDraftLoads();
    }

    handleDraftLoadsSearchChange(event) {
        this.draftLoadsSearchInput = event.target?.value || '';
    }

    handleDraftLoadsSearchKeydown(event) {
        if (event.key !== 'Enter') {
            return;
        }

        event.preventDefault();
        this.searchDraftLoads();
    }

    searchDraftLoads() {
        this.draftLoadsSearchTerm = (this.draftLoadsSearchInput || '').trim();
        this.draftLoadsPage = 1;
        this.loadDraftLoads();
    }

    clearDraftLoadsSearch() {
        this.draftLoadsSearchInput = '';
        this.draftLoadsSearchTerm = '';
        this.draftLoadsPage = 1;
        this.loadDraftLoads();
    }

    previousDraftLoadsPage() {
        if (this.disableDraftLoadsPrevious) {
            return;
        }

        this.draftLoadsPage -= 1;
        this.loadDraftLoads();
    }

    nextDraftLoadsPage() {
        if (this.disableDraftLoadsNext) {
            return;
        }

        this.draftLoadsPage += 1;
        this.loadDraftLoads();
    }

    openApproveDraftModal(event) {
        const loadId = event.currentTarget?.dataset?.id;

        if (!loadId) {
            return;
        }

        this.pendingApproveDraftLoadId = loadId;
        this.showApproveDraftModal = true;
    }

    closeApproveDraftModal() {
        if (this.isApproving) {
            return;
        }

        this.pendingApproveDraftLoadId = '';
        this.showApproveDraftModal = false;
    }

    async confirmApproveDraftLoad() {
        const loadId = this.pendingApproveDraftLoadId;

        if (!loadId) {
            return;
        }

        this.activeDraftLoadId = loadId;
        this.isApproving = true;
        this.draftLoadsErrorMessage = '';

        try {
            await approveAutoFillLoad({ loadId });
            await this.loadDraftLoads();

            if (loadId === this.createdRecordId) {
                this.autoFillStatus = AUTOFILL_STATUS_APPROVED;
            }

            this.pendingApproveDraftLoadId = '';
            this.showApproveDraftModal = false;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Draft approved',
                    message: 'The AutoFill draft load was approved.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.draftLoadsErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Approval failed',
                    message: this.draftLoadsErrorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isApproving = false;
            this.activeDraftLoadId = '';
        }
    }

    openRejectDraftModal(event) {
        const loadId = event.currentTarget?.dataset?.id;

        if (!loadId) {
            return;
        }

        this.pendingRejectDraftLoadId = loadId;
        this.rejectionReason = '';
        this.showRejectDraftModal = true;
    }

    closeRejectDraftModal() {
        if (this.isRejecting) {
            return;
        }

        this.pendingRejectDraftLoadId = '';
        this.rejectionReason = '';
        this.showRejectDraftModal = false;
    }

    handleRejectReasonChange(event) {
        this.rejectionReason = event.target.value;
    }

    async confirmRejectDraftLoad() {
        const loadId = this.pendingRejectDraftLoadId;

        if (!loadId) {
            return;
        }

        this.activeDraftLoadId = loadId;
        this.isRejecting = true;
        this.draftLoadsErrorMessage = '';

        try {
            const result = await rejectAutoFillLoad({ loadId, rejectionReason: this.rejectionReason });
            await this.loadDraftLoads();

            if (loadId === this.createdRecordId) {
                this.autoFillStatus = AUTOFILL_STATUS_REJECTED;
                this.createdRecordDeleted = Boolean(result?.deleted);
            }

            this.pendingRejectDraftLoadId = '';
            this.rejectionReason = '';
            this.showRejectDraftModal = false;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Draft rejected',
                    message: result?.message || 'The AutoFill draft load was rejected.',
                    variant: 'success',
                    mode: 'dismissable'
                })
            );
        } catch (error) {
            this.draftLoadsErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reject failed',
                    message: this.draftLoadsErrorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isRejecting = false;
            this.activeDraftLoadId = '';
        }
    }

    viewDraftLoad(event) {
        const loadId = event.currentTarget?.dataset?.id;

        if (!loadId) {
            return;
        }

        this.navigateToLoad(loadId);
    }

    async openDetectedFieldsModal(event) {
        const loadId = event.currentTarget?.dataset?.id;
        const selectedLoad = (this.draftLoads || []).find(
            (load) => load.id === loadId
        );

        if (!selectedLoad) {
            return;
        }

        this.detectedFieldsModalTitle =
            `${selectedLoad.loadName || 'Load'} detected fields`;
        this.detectedFieldsModalRows = selectedLoad.detectedFieldsRows || [];
        this.detectedFieldsSavedRows =
            selectedLoad.detectedFieldsSavedRows || [];
        this.detectedFieldsNotSavedRows =
            selectedLoad.detectedFieldsNotSavedRows || [];
        this.detectedFieldsRawRows =
            selectedLoad.detectedFieldsRawRows || [];
        this.detectedFieldsChildTables =
            selectedLoad.detectedFieldsChildTables || [];
        this.detectedFieldsSavedCountLabel =
            selectedLoad.savedFieldCountLabel || '0';
        this.detectedFieldsNotSavedCountLabel =
            selectedLoad.notSavedFieldCountLabel || '0';
        this.detectedFieldsRawCountLabel =
            selectedLoad.rawDetectedFieldCountLabel || '0';
        this.detectedSourceText = selectedLoad.sourceText || '';
        this.detectedFieldsFiles = [];
        this.selectedDetectedFileId = '';
        this.detectedFilePreviewError = '';
        this.showDetectedFieldsModal = true;

        await this.loadDetectedFilePreviews(loadId);
    }

    async loadDetectedFilePreviews(loadId) {
        if (!loadId) {
            return;
        }

        this.clearDetectedPreviewTimer();
        this.isLoadingDetectedFilePreview = true;
        this.detectedFilePreviewError = '';

        try {
            const files = await getLoadFilePreviews({ loadId });
            const normalizedFiles = (files || []).map((file) => {
                const isPdf = Boolean(file.isPdf);
                const isImage = this.isDetectedImageFile(file);
                const canInlinePreview = isPdf || isImage;

                return {
                    ...file,
                    title: file.title || 'Uploaded file',
                    isPdf,
                    isImage,
                    canInlinePreview,
                    previewStage: 0,
                    previewUrl: canInlinePreview
                        ? this.buildInitialDetectedPreviewUrl({
                            ...file,
                            isPdf,
                            isImage
                        })
                        : '',
                    buttonVariant: 'neutral'
                };
            });

            const firstPdf = normalizedFiles.find((file) => file.isPdf);
            const firstImage = normalizedFiles.find((file) => file.isImage);
            const firstFile =
                firstPdf || firstImage || normalizedFiles[0] || null;

            this.selectedDetectedFileId =
                firstFile?.contentDocumentId || '';

            this.detectedFieldsFiles = normalizedFiles.map((file) => ({
                ...file,
                buttonVariant:
                    file.contentDocumentId === this.selectedDetectedFileId
                        ? 'brand'
                        : 'neutral'
            }));

            if (firstFile?.canInlinePreview) {
                this.startDetectedPreviewTimer();
            } else {
                this.isLoadingDetectedFilePreview = false;
            }
        } catch (error) {
            this.detectedFieldsFiles = [];
            this.selectedDetectedFileId = '';
            this.isLoadingDetectedFilePreview = false;
            this.detectedFilePreviewError = this.getErrorMessage(error);
        }
    }

    isDetectedImageFile(file) {
        const fileType = String(file?.fileType || '').toUpperCase();
        const fileExtension = String(file?.fileExtension || '')
            .replace(/^\./, '')
            .toUpperCase();

        return (
            IMAGE_FILE_TYPES.has(fileType) ||
            IMAGE_FILE_TYPES.has(fileExtension)
        );
    }

    buildInitialDetectedPreviewUrl(file) {
        if (!file?.contentVersionId) {
            return '';
        }

        if (file.isPdf) {
            return this.buildDetectedFileRenditionUrl(
                file.contentVersionId,
                'SVGZ'
            );
        }

        if (file.isImage) {
            return this.buildDetectedImagePreviewUrl(file.contentVersionId);
        }

        return '';
    }

    buildDetectedImagePreviewUrl(contentVersionId) {
        if (!contentVersionId) {
            return '';
        }

        const safeVersionId = encodeURIComponent(contentVersionId);
        const cacheBust = Date.now();

        return (
            `/sfc/servlet.shepherd/version/download/${safeVersionId}` +
            `?_=${cacheBust}`
        );
    }

    buildDetectedFileRenditionUrl(contentVersionId, rendition) {
        if (!contentVersionId) {
            return '';
        }

        const safeVersionId = encodeURIComponent(contentVersionId);
        const safeRendition = encodeURIComponent(rendition || 'SVGZ');
        const pageParameter = rendition === 'SVGZ' ? '&page=0' : '';
        const cacheBust = Date.now();

        return (
            '/sfc/servlet.shepherd/version/renditionDownload' +
            `?rendition=${safeRendition}` +
            `&versionId=${safeVersionId}` +
            pageParameter +
            '&operationContext=CHATTER' +
            `&_=${cacheBust}`
        );
    }

    startDetectedPreviewTimer(timeoutMs = 15000) {
        this.clearDetectedPreviewTimer();

        this.detectedPreviewLoadTimer = window.setTimeout(() => {
            const selectedFile = this.selectedDetectedFile;

            if (!selectedFile?.canInlinePreview) {
                this.isLoadingDetectedFilePreview = false;
                return;
            }

            if ((selectedFile.previewStage || 0) === 0) {
                this.useDetectedPreviewFallback();
                return;
            }

            this.isLoadingDetectedFilePreview = false;
            this.detectedFilePreviewError =
                'Salesforce could not generate the inline preview. Use Open full preview to view the document.';
        }, timeoutMs);
    }

    clearDetectedPreviewTimer() {
        if (this.detectedPreviewLoadTimer) {
            window.clearTimeout(this.detectedPreviewLoadTimer);
            this.detectedPreviewLoadTimer = null;
        }
    }

    useDetectedPreviewFallback() {
        const selectedFile = this.selectedDetectedFile;

        if (!selectedFile?.contentVersionId) {
            this.isLoadingDetectedFilePreview = false;
            this.detectedFilePreviewError =
                'The preview is unavailable because the file version could not be found.';
            return;
        }

        this.detectedFieldsFiles = (this.detectedFieldsFiles || []).map(
            (file) => {
                if (file.contentDocumentId !== this.selectedDetectedFileId) {
                    return file;
                }

                return {
                    ...file,
                    previewStage: 1,
                    previewUrl: this.buildDetectedFileRenditionUrl(
                        file.contentVersionId,
                        'THUMB720BY480'
                    )
                };
            }
        );

        this.isLoadingDetectedFilePreview = true;
        this.startDetectedPreviewTimer(10000);
    }

    handleDetectedPreviewLoad() {
        this.clearDetectedPreviewTimer();
        this.isLoadingDetectedFilePreview = false;
        this.detectedFilePreviewError = '';
    }

    handleDetectedPreviewError() {
        const selectedFile = this.selectedDetectedFile;

        if (
            selectedFile?.canInlinePreview &&
            (selectedFile.previewStage || 0) === 0
        ) {
            this.useDetectedPreviewFallback();
            return;
        }

        this.clearDetectedPreviewTimer();
        this.isLoadingDetectedFilePreview = false;
        this.detectedFilePreviewError =
            'Salesforce could not generate the inline preview. Use Open full preview to view the document.';
    }

    selectDetectedFilePreview(event) {
        const contentDocumentId = event.currentTarget?.dataset?.id;

        if (!contentDocumentId) {
            return;
        }

        this.clearDetectedPreviewTimer();
        this.selectedDetectedFileId = contentDocumentId;
        this.detectedFilePreviewError = '';

        this.detectedFieldsFiles = (this.detectedFieldsFiles || []).map(
            (file) => {
                const isSelected =
                    file.contentDocumentId === contentDocumentId;

                if (!isSelected) {
                    return {
                        ...file,
                        buttonVariant: 'neutral'
                    };
                }

                return {
                    ...file,
                    buttonVariant: 'brand',
                    previewStage: 0,
                    previewUrl: file.canInlinePreview
                        ? this.buildInitialDetectedPreviewUrl(file)
                        : ''
                };
            }
        );

        if (this.selectedDetectedFileCanInlinePreview) {
            this.isLoadingDetectedFilePreview = true;
            this.startDetectedPreviewTimer();
        } else {
            this.isLoadingDetectedFilePreview = false;
        }
    }

    openDetectedFileInSalesforce() {
        const selectedFile = this.selectedDetectedFile;

        if (!selectedFile?.contentDocumentId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: selectedFile.contentDocumentId
            }
        });
    }

    closeDetectedFieldsModal() {
        this.clearDetectedPreviewTimer();
        this.showDetectedFieldsModal = false;
        this.detectedFieldsModalRows = [];
        this.detectedFieldsSavedRows = [];
        this.detectedFieldsNotSavedRows = [];
        this.detectedFieldsRawRows = [];
        this.detectedFieldsChildTables = [];
        this.detectedFieldsModalTitle = '';
        this.detectedFieldsSavedCountLabel = '0';
        this.detectedFieldsNotSavedCountLabel = '0';
        this.detectedFieldsRawCountLabel = '0';
        this.detectedFieldsFiles = [];
        this.detectedSourceText = '';
        this.selectedDetectedFileId = '';
        this.isLoadingDetectedFilePreview = false;
        this.detectedFilePreviewError = '';
    }

    openUploadRawJsonModal() {
        this.openRawJsonModal('Manual upload raw API response', this.uploadRawJson);
    }

    openDraftRawJsonModal(event) {
        const loadId = event.currentTarget?.dataset?.id;
        const selectedLoad = (this.draftLoads || []).find((load) => load.id === loadId);

        if (!selectedLoad) {
            return;
        }

        this.openRawJsonModal(`${selectedLoad.loadName || 'Load'} raw API response`, selectedLoad.rawResponseJson);
    }

    openRawJsonModal(title, rawJson) {
        this.rawJsonModalTitle = title || 'Raw API response';
        this.rawJsonText = this.formatRawJsonForDisplay(rawJson);
        this.showRawJsonModal = true;
    }

    closeRawJsonModal() {
        this.showRawJsonModal = false;
        this.rawJsonModalTitle = '';
        this.rawJsonText = '';
    }

    handleDescriptionChange(event) {
        this.emailContent = event.target.value;
    }

    async handleFilesChange(event) {
        this.resetMessages();

        const selectedFiles = Array.from(event.target.files || []);

        if (!selectedFiles.length) {
            this.files = [];
            this.selectedFileNames = [];
            return;
        }

        try {
            this.files = await Promise.all(
                selectedFiles.map((file) => this.readFile(file))
            );

            this.selectedFileNames = this.files.map((file) => file.fileName);
        } catch (error) {
            this.files = [];
            this.selectedFileNames = [];
            this.errorMessage = this.getErrorMessage(error);
            this.resetFileInput();
        }
    }

    async loadExtractedItems() {
    this.isLoadingExtractedItems = true;
    this.extractedItemsErrorMessage = '';

    try {
        const result = await getExtractedItems({
            pageNumber: this.extractedItemsPage,
            pageSize: this.extractedItemsPageSize
        });

        this.extractedItemsPage = result.page || this.extractedItemsPage;
        this.extractedItemsPageSize = result.pageSize || this.extractedItemsPageSize;
        this.extractedItemsTotal = result.total || 0;

        this.extractedItemsRows = (result.items || []).map((item) => {
            return {
                ...item,
                formattedExtractedAt: this.formatDateTime(item.extractedAt),
                objectLabel: item.salesforceObjectType || 'Unknown',
                recordLabel: item.salesforceRecordId || 'Not created',
                senderLabel: item.senderEmail || 'None',
                fieldsLabel: item.extractedFieldsSummary || 'No extracted fields'
            };
        });
    } catch (error) {
        this.extractedItemsRows = [];
        this.extractedItemsErrorMessage = this.getErrorMessage(error);
    } finally {
        this.isLoadingExtractedItems = false;
    }
}

refreshExtractedItems() {
    this.loadExtractedItems();
}

previousExtractedItemsPage() {
    if (this.extractedItemsPage <= 1) {
        return;
    }

    this.extractedItemsPage -= 1;
    this.loadExtractedItems();
}

nextExtractedItemsPage() {
    if (this.extractedItemsPage * this.extractedItemsPageSize >= this.extractedItemsTotal) {
        return;
    }

    this.extractedItemsPage += 1;
    this.loadExtractedItems();
}

    async sendToApi() {
        this.resetMessages();

        const emailContent = this.emailContent?.trim() || '';
        const files = Array.isArray(this.files) ? this.files : [];
        const hasEmailContent = Boolean(emailContent);
        const hasAttachments = files.length > 0;

        if (!hasEmailContent && !hasAttachments) {
            this.errorMessage =
                'Add email/document notes or upload at least one attachment.';
            return;
        }

        const emailContentForApi = hasEmailContent ? emailContent : 'text';

        this.isSending = true;

        try {
            const result = await sendEmailContent({
                emailContent: emailContentForApi,
                files
            });

            if (!result) {
                this.errorMessage = 'Salesforce did not return a response.';
                return;
            }

            this.uploadRawJson = result.rawResponseJson || result.responseBody || '';
            this.itemId = result.itemId || this.extractItemIdFromResponse(result.responseBody) || '';
            this.detectedDocumentType = result.detectedDocumentType || this.findValueFromResponse(result.responseBody, ['DetectedDocumentType', 'documentType']) || '';
            this.documentConfidence = result.documentConfidence ??
                this.findValueFromResponse(
                    result.responseBody,
                    ['Confidence', 'confidence', 'OverallConfidence', 'overallConfidence']
                ) ??
                '';
            this.classificationConfidence = result.classificationConfidence ??
                this.findValueFromResponse(
                    result.responseBody,
                    ['ClassificationConfidence', 'classificationConfidence']
                ) ??
                '';
            this.autoFillSource = result.autoFillSource || 'Manual Upload';
            this.autoFillFieldCount = result.fieldCount === null || result.fieldCount === undefined ? '' : result.fieldCount;
            this.autoFillAllFieldsDetected = result.allFieldsDetected === null || result.allFieldsDetected === undefined ? null : result.allFieldsDetected;
            this.hydrateExtractRowsFromResponse(result.responseBody);

            if (!result.success) {
                this.errorMessage = result.message || 'The request could not be completed.';
                return;
            }

            this.createdRecordId = result.recordId || '';
            this.createdObjectType = result.objectType || '';
            this.createdRecordDeleted = false;
            this.autoFillStatus = result.autoFillStatus ||
                (this.createdObjectType === LOAD_OBJECT_API_NAME ? AUTOFILL_STATUS_DIRECT : '');
            this.successMessage = result.message || 'The Salesforce record was created successfully.';

            if (this.itemId) {
                await this.loadExtractedDocument();
            }
            await this.loadExtractedItems();
            await this.loadDraftLoads();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'AutoFill complete',
                    message: this.createdRecordId
                        ? `Record ${this.createdRecordId} was created successfully.`
                        : this.successMessage,
                    variant: 'success',
                    mode: 'dismissable'
                })
            );
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'AutoFill failed',
                    message: this.errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSending = false;
        }
    }

    async loadExtractedDocument() {
        if (!this.itemId) {
            return;
        }

        this.isLoadingExtract = true;
        this.extractErrorMessage = '';

        try {
            const scanResult = await getExtractedDocument({ itemId: this.itemId });

            if (!scanResult) {
                return;
            }

            this.documentStatus = scanResult.status || '';
            this.webhookStatus = scanResult.webhookStatus || '';
            this.detectedDocumentType = scanResult.detectedDocumentType || this.detectedDocumentType;
            this.documentConfidence = scanResult.confidence ?? this.documentConfidence;
            this.classificationConfidence = scanResult.classificationConfidence ??
                this.findValueFromResponse(
                    scanResult.rawJson,
                    ['ClassificationConfidence', 'classificationConfidence']
                ) ??
                this.classificationConfidence;
            this.failureReason = scanResult.failureReason || '';
            this.processedAt = this.formatDateTime(scanResult.processedAt || '');

            if (scanResult.extractedFields && scanResult.extractedFields.length) {
                this.extractRows = this.normalizeFieldRows(scanResult.extractedFields);
            } else if (scanResult.rawJson) {
                this.hydrateExtractRowsFromResponse(scanResult.rawJson);
            }
        } catch (error) {
            this.extractErrorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoadingExtract = false;
        }
    }

    async approveLoad() {
        if (!this.createdRecordId || !this.canApproveReject) {
            return;
        }

        this.pendingApproveDraftLoadId = this.createdRecordId;
        this.showApproveDraftModal = true;
    }

    async rejectLoad() {
        if (!this.createdRecordId || !this.canApproveReject) {
            return;
        }

        this.pendingRejectDraftLoadId = this.createdRecordId;
        this.rejectionReason = '';
        this.showRejectDraftModal = true;
    }

    viewCreatedRecord() {
        if (!this.createdRecordId || this.createdRecordDeleted) {
            return;
        }

        this.navigateToLoad(this.createdRecordId);
    }


    navigateToLoad(loadId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: loadId,
                actionName: 'view'
            }
        });
    }

    clearForm() {
        this.emailContent = '';
        this.files = [];
        this.selectedFileNames = [];
        this.resetMessages();
        this.resetFileInput();
    }

    resetMessages() {
        this.errorMessage = '';
        this.successMessage = '';
        this.extractErrorMessage = '';
        this.createdRecordId = '';
        this.createdObjectType = '';
        this.createdRecordDeleted = false;
        this.itemId = '';
        this.autoFillStatus = '';
        this.documentStatus = '';
        this.webhookStatus = '';
        this.detectedDocumentType = '';
        this.documentConfidence = '';
        this.classificationConfidence = '';
        this.autoFillSource = '';
        this.autoFillFieldCount = '';
        this.autoFillAllFieldsDetected = null;
        this.failureReason = '';
        this.processedAt = '';
        this.extractRows = [];
        this.uploadRawJson = '';
        this.closeRawJsonModal();
    }

    resetFileInput() {
        const fileInput = this.template.querySelector('lightning-input[type="file"]');

        if (fileInput) {
            fileInput.value = null;
        }
    }

    readFile(file) {
        return new Promise((resolve, reject) => {
            if (file.size > MAX_FILE_BYTES) {
                reject(new Error(`${file.name} is too large. Maximum size is 4.5 MB.`));
                return;
            }

            const reader = new FileReader();

            reader.onload = () => {
                const result = reader.result;
                const separatorIndex = result.indexOf(',');

                if (separatorIndex === -1) {
                    reject(new Error(`Could not process ${file.name}.`));
                    return;
                }

                resolve({
                    fileName: file.name,
                    contentType: file.type || 'application/octet-stream',
                    base64Data: result.substring(separatorIndex + 1)
                });
            };

            reader.onerror = () => {
                reject(new Error(`Could not read ${file.name}.`));
            };

            reader.readAsDataURL(file);
        });
    }

    hydrateExtractRowsFromResponse(responseBody) {
        const parsed = this.parseJson(responseBody);

        if (!parsed) {
            return;
        }

        const extractedFields = this.findNestedValue(parsed, ['ExtractedFields', 'extractedFields']);
        const fieldConfidences = this.findNestedValue(parsed, ['FieldConfidences', 'fieldConfidences']) || {};

        if (extractedFields && typeof extractedFields === 'object') {
            this.extractRows = this.objectToRows(extractedFields, '', fieldConfidences);
        }
    }

    normalizeFieldRows(rows) {
        return rows
            .filter((row) => row)
            .map((row, index) => ({
                id: `${row.fieldName || 'field'}-${index}`,
                fieldName: row.fieldName || '',
                label: this.formatFieldLabel(row.fieldName || ''),
                displayValue: this.formatDisplayValue(this.extractFieldValue(row.value === undefined ? row : row.value)),
                confidenceLabel: this.formatConfidenceValue(row.confidence === undefined ? this.extractFieldConfidence(row) : row.confidence) || 'Not provided'
            }))
            .filter((row) => row.label || row.displayValue);
    }

    objectToRows(source, prefix = '', fieldConfidences = {}) {
        if (!source || typeof source !== 'object') {
            return [];
        }

        if (Array.isArray(source)) {
            return source
                .flatMap((value, index) => {
                    const fullKey = `${prefix || 'Item'} ${index + 1}`;

                    if (value && typeof value === 'object') {
                        return this.objectToRows(value, fullKey, fieldConfidences);
                    }

                    return [{
                        id: `${prefix || 'Item'}-${index}`,
                        fieldName: fullKey,
                        label: this.formatFieldLabel(fullKey),
                        displayValue: this.formatDisplayValue(value),
                        confidenceLabel: this.formatConfidenceValue(this.getFieldConfidence(fieldConfidences, fullKey)) || 'Not provided'
                    }];
                })
                .filter((row) => row.displayValue !== '');
        }

        return Object.keys(source)
            .sort()
            .flatMap((key) => {
                const value = source[key];
                const fullKey = prefix ? `${prefix}.${key}` : key;

                if (this.isFieldResultObject(value)) {
                    return [{
                        id: fullKey,
                        fieldName: fullKey,
                        label: this.formatFieldLabel(fullKey),
                        displayValue: this.formatDisplayValue(this.extractFieldValue(value)),
                        confidenceLabel: this.formatConfidenceValue(this.extractFieldConfidence(value) || this.getFieldConfidence(fieldConfidences, fullKey)) || 'Not provided'
                    }];
                }

                if (value && typeof value === 'object') {
                    return this.objectToRows(value, fullKey, fieldConfidences);
                }

                return [{
                    id: fullKey,
                    fieldName: fullKey,
                    label: this.formatFieldLabel(fullKey),
                    displayValue: this.formatDisplayValue(value),
                    confidenceLabel: this.formatConfidenceValue(this.getFieldConfidence(fieldConfidences, fullKey)) || 'Not provided'
                }];
            })
            .filter((row) => row.displayValue !== '');
    }

    parseV2ChildTables(rawResponseJson) {
        const parsed = this.parseJson(rawResponseJson);

        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return [];
        }

        const metadata = this.getDirectObjectByKeys(parsed, ['Metadata', 'metadata']) || {};
        const objectGraph = this.getDirectObjectByKeys(metadata, ['ObjectGraph', 'objectGraph']) || {};
        const collections =
            this.getDirectObjectByKeys(metadata, ['Collections', 'collections']) ||
            this.getDirectObjectByKeys(parsed, ['Collections', 'collections']) ||
            this.getDirectObjectByKeys(objectGraph, ['Collections', 'collections']);

        if (!collections) {
            return [];
        }

        return Object.keys(collections)
            .sort((left, right) => left.localeCompare(right))
            .flatMap((collectionName, collectionIndex) => {
                const sourceRows = collections[collectionName];

                if (!Array.isArray(sourceRows) || sourceRows.length === 0) {
                    return [];
                }

                const normalizedRows = sourceRows.map((row) => {
                    if (row && typeof row === 'object' && !Array.isArray(row)) {
                        return row;
                    }

                    return { Value: row };
                });
                const fieldNames = [];
                const seenFieldNames = new Set();

                normalizedRows.forEach((row) => {
                    Object.keys(row).forEach((fieldName) => {
                        const normalizedFieldName = this.normalizeKey(fieldName);

                        if (!normalizedFieldName || seenFieldNames.has(normalizedFieldName)) {
                            return;
                        }

                        seenFieldNames.add(normalizedFieldName);
                        fieldNames.push(fieldName);
                    });
                });

                if (fieldNames.length === 0) {
                    return [];
                }

                const columns = fieldNames.map((fieldName, columnIndex) => ({
                    id: `child-column-${collectionIndex}-${columnIndex}`,
                    key: fieldName,
                    label: this.formatV2ChildLabel(fieldName)
                }));
                const rows = normalizedRows.map((row, rowIndex) => ({
                    id: `child-row-${collectionIndex}-${rowIndex}`,
                    indexLabel: String(rowIndex + 1),
                    cells: columns.map((column, columnIndex) => {
                        const rawCellValue = this.getDirectValueByNormalizedKey(row, column.key);
                        const extractedValue = this.extractFieldValue(rawCellValue);
                        const confidenceLabel = this.formatConfidenceValue(
                            this.extractFieldConfidence(rawCellValue)
                        );

                        return {
                            id: `child-cell-${collectionIndex}-${rowIndex}-${columnIndex}`,
                            displayValue: this.formatDisplayValue(extractedValue) || 'Not provided',
                            confidenceLabel,
                            hasConfidence: Boolean(confidenceLabel)
                        };
                    })
                }));

                return [{
                    id: `child-table-${collectionIndex}-${this.normalizeKey(collectionName)}`,
                    label: this.formatV2ChildLabel(collectionName),
                    rowCountLabel: String(rows.length),
                    columns,
                    rows
                }];
            });
    }

    formatV2ChildLabel(value) {
        const sourceValue = String(value || '');
        const cleanedValue = sourceValue
            .replace(/^freighttm__/i, '')
            .replace(/^freight_tm_/i, '')
            .replace(/__(c|r)$/i, '');
        const formattedValue = this.formatFieldLabel(cleanedValue) || sourceValue;

        return formattedValue
            ? `${formattedValue.charAt(0).toUpperCase()}${formattedValue.slice(1)}`
            : '';
    }

    getDirectObjectByKeys(source, possibleKeys) {
        if (!source || typeof source !== 'object' || Array.isArray(source)) {
            return null;
        }

        const value = this.getDirectValueByKeys(source, possibleKeys);
        return value && typeof value === 'object' && !Array.isArray(value)
            ? value
            : null;
    }

    getDirectValueByKeys(source, possibleKeys) {
        if (!source || typeof source !== 'object' || Array.isArray(source)) {
            return undefined;
        }

        const normalizedKeys = possibleKeys.map((key) => this.normalizeKey(key));

        for (const key of Object.keys(source)) {
            if (normalizedKeys.includes(this.normalizeKey(key))) {
                return source[key];
            }
        }

        return undefined;
    }

    getDirectValueByNormalizedKey(source, requestedKey) {
        if (!source || typeof source !== 'object' || Array.isArray(source)) {
            return undefined;
        }

        const normalizedRequestedKey = this.normalizeKey(requestedKey);

        for (const key of Object.keys(source)) {
            if (this.normalizeKey(key) === normalizedRequestedKey) {
                return source[key];
            }
        }

        return undefined;
    }

    parseDetectedFields(detectedFieldsJson) {
        return this.parseDetectedFieldsAudit(detectedFieldsJson).allRows;
    }

    parseDetectedFieldsAudit(detectedFieldsJson) {
        const parsed = this.parseJson(detectedFieldsJson);

        if (!parsed) {
            return {
                isStructured: false,
                savedRows: [],
                notSavedRows: [],
                rawRows: [],
                allRows: []
            };
        }

        const savedSource = Array.isArray(parsed.savedToLoad) ? parsed.savedToLoad : [];
        const notSavedSource = Array.isArray(parsed.detectedNotSavedToLoad) ? parsed.detectedNotSavedToLoad : [];
        const rawSource = Array.isArray(parsed.rawDetectedFields) ? parsed.rawDetectedFields : [];

        if (savedSource.length || notSavedSource.length || rawSource.length || parsed.summary) {
            const savedRows = savedSource.map((row, index) => this.auditRowToDisplayRow(row, `saved-${index}`, true));
            const notSavedRows = notSavedSource.map((row, index) => this.auditRowToDisplayRow(row, `not-saved-${index}`, false));
            const rawRows = rawSource.map((row, index) => this.auditRowToDisplayRow(row, `raw-${index}`, false));

            return {
                isStructured: true,
                savedRows,
                notSavedRows,
                rawRows,
                allRows: [...savedRows, ...notSavedRows]
            };
        }

        const legacyRows = this.objectToRows(parsed);

        return {
            isStructured: false,
            savedRows: [],
            notSavedRows: legacyRows,
            rawRows: legacyRows,
            allRows: legacyRows
        };
    }

    auditRowToDisplayRow(row, fallbackId, savedToLoad) {
        const fieldName = row?.fieldName || row?.label || row?.loadFieldApiName || fallbackId;
        const loadFieldApiName = row?.loadFieldApiName || row?.salesforceFieldApiName || '';
        const loadFieldLabel = row?.loadFieldLabel || loadFieldApiName || '';
        const reason = row?.reason || '';
        const labelParts = [this.formatFieldLabel(fieldName)];

        if (savedToLoad && loadFieldApiName) {
            labelParts.push(`→ ${loadFieldLabel || loadFieldApiName}`);
        }

        return {
            id: row?.id || `${fallbackId}-${this.normalizeKey(fieldName)}-${this.normalizeKey(loadFieldApiName)}`,
            fieldName,
            label: labelParts.filter(Boolean).join(' '),
            loadFieldApiName,
            loadFieldLabel,
            displayValue: this.formatDisplayValue(row?.value),
            confidenceLabel: this.formatConfidenceValue(row?.confidence) || 'Not provided',
            reasonLabel: reason || (savedToLoad ? 'Saved to Load' : 'Not saved to Load')
        };
    }

    isFieldResultObject(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) {
            return false;
        }

        const keys = Object.keys(value).map((key) => this.normalizeKey(key));
        const hasValueKey = keys.some((key) => ['value', 'rawvalue', 'extractedvalue', 'text', 'content'].includes(key));
        const hasConfidenceKey = keys.some((key) => ['confidence', 'score', 'confidencepercent', 'confidencepercentage'].includes(key));

        return hasValueKey || hasConfidenceKey;
    }

    extractFieldValue(value) {
        if (!this.isFieldResultObject(value)) {
            return value;
        }

        const possibleKeys = ['Value', 'value', 'RawValue', 'rawValue', 'ExtractedValue', 'extractedValue', 'Text', 'text', 'Content', 'content'];

        for (const key of Object.keys(value)) {
            if (possibleKeys.map((possibleKey) => this.normalizeKey(possibleKey)).includes(this.normalizeKey(key))) {
                return value[key];
            }
        }

        return '';
    }

    getFieldConfidence(fieldConfidences, fieldName) {
        if (!fieldConfidences || typeof fieldConfidences !== 'object' || !fieldName) {
            return '';
        }

        const normalizedFieldName = this.normalizeKey(fieldName);

        for (const key of Object.keys(fieldConfidences)) {
            if (this.normalizeKey(key) === normalizedFieldName) {
                return fieldConfidences[key];
            }
        }

        return '';
    }

    extractFieldConfidence(value) {
        if (!value || typeof value !== 'object') {
            return '';
        }

        const possibleKeys = ['Confidence', 'confidence', 'Score', 'score', 'ConfidencePercent', 'confidencePercent', 'ConfidencePercentage', 'confidencePercentage'];

        for (const key of Object.keys(value)) {
            if (possibleKeys.map((possibleKey) => this.normalizeKey(possibleKey)).includes(this.normalizeKey(key))) {
                return value[key];
            }
        }

        return '';
    }

    extractItemIdFromResponse(responseBody) {
        return this.findValueFromResponse(responseBody, ['ItemId', 'itemId']);
    }

    findValueFromResponse(responseBody, keys) {
        const parsed = this.parseJson(responseBody);

        if (!parsed) {
            return '';
        }

        const value = this.findNestedValue(parsed, keys);
        return value === undefined || value === null ? '' : String(value);
    }

    formatRawJsonForDisplay(rawJson) {
        if (!rawJson) {
            return '';
        }

        const parsed = this.parseJson(rawJson);

        if (parsed) {
            return JSON.stringify(parsed, null, 2);
        }

        return String(rawJson);
    }

    parseJson(responseBody) {
        if (!responseBody) {
            return null;
        }

        try {
            return typeof responseBody === 'string'
                ? JSON.parse(responseBody)
                : responseBody;
        } catch (error) {
            return null;
        }
    }

    extractDetectedSourceText(rawResponseJson) {
        const parsed = this.parseJson(rawResponseJson);

        if (!parsed) {
            return '';
        }

        const value = this.findNestedValue(parsed, [
            'AutoFillSourceText',
            'autoFillSourceText',
            'SubmittedEmailContent',
            'submittedEmailContent',
            'EmailContent',
            'emailContent',
            'EmailBody',
            'emailBody',
            'PlainTextBody',
            'plainTextBody',
            'TextBody',
            'textBody',
            'SourceText',
            'sourceText'
        ]);
        const text = value === undefined || value === null
            ? ''
            : String(value).trim();

        return this.normalizeKey(text) === 'text' ? '' : text;
    }

    findNestedValue(source, possibleKeys) {
        if (!source || typeof source !== 'object') {
            return undefined;
        }

        const normalizedKeys = possibleKeys.map((key) => this.normalizeKey(key));

        for (const key of Object.keys(source)) {
            if (normalizedKeys.includes(this.normalizeKey(key))) {
                return source[key];
            }
        }

        for (const key of Object.keys(source)) {
            const value = source[key];

            if (value && typeof value === 'object' && !Array.isArray(value)) {
                const nestedValue = this.findNestedValue(value, possibleKeys);

                if (nestedValue !== undefined && nestedValue !== null) {
                    return nestedValue;
                }
            }
        }

        return undefined;
    }

    resolveDraftSourceLabel(row) {
        const directSource = row?.source || row?.autoFillSource;
        let rawSource = directSource;

        if (!rawSource && row?.rawResponseJson) {
            const parsed = this.parseJson(row.rawResponseJson);
            rawSource = parsed
                ? this.findNestedValue(parsed, [
                    'AutoFillSource',
                    'autoFillSource',
                    'Source',
                    'source',
                    'UploadSource',
                    'uploadSource'
                ])
                : '';
        }

        return this.normalizeSourceLabel(rawSource) || 'Not available';
    }

    normalizeSourceLabel(value) {
        const source = String(value || '').trim();

        if (!source) {
            return '';
        }

        const normalized = this.normalizeKey(source);

        if (normalized.includes('webhook') || normalized.includes('email')) {
            return 'Email';
        }

        if (normalized.includes('manual')) {
            return 'Manual Upload';
        }

        if (normalized.includes('api')) {
            return 'API Upload';
        }

        return source;
    }

    getSourceIcon(row) {
        const sourceLabel = this.resolveDraftSourceLabel(row);

        if (sourceLabel === 'Email') {
            return 'utility:email';
        }

        if (sourceLabel === 'Manual Upload') {
            return 'utility:upload';
        }

        if (sourceLabel === 'API Upload') {
            return 'utility:connected_apps';
        }

        return 'utility:question';
    }

    getSourceClass(row) {
        const sourceLabel = this.resolveDraftSourceLabel(row);
        const suffix = sourceLabel === 'Email'
            ? 'email'
            : sourceLabel === 'Manual Upload'
                ? 'manual'
                : sourceLabel === 'API Upload'
                    ? 'api'
                    : 'default';

        return `source-chip ${suffix}`;
    }

    normalizeKey(value) {
        return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    }

    formatFieldLabel(value) {
        return String(value || '')
            .replace(/\./g, ' / ')
            .replace(/__/g, ' ')
            .replace(/_/g, ' ')
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            .replace(/\s+/g, ' ')
            .trim();
    }

    formatDisplayValue(value) {
        if (value === null || value === undefined) {
            return '';
        }

        if (Array.isArray(value)) {
            return value.map((item) => this.formatDisplayValue(item)).filter(Boolean).join(', ');
        }

        if (typeof value === 'object') {
            return Object.keys(value)
                .map((key) => `${this.formatFieldLabel(key)}: ${this.formatDisplayValue(value[key])}`)
                .join('\n');
        }

        return String(value);
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(date);
    }


    isDraftStatus(status) {
        return status === AUTOFILL_STATUS_DRAFT || status === AUTOFILL_STATUS_DIRECT;
    }

    getStatusPillClass(status) {
        const base = 'status-pill';

        if (status === AUTOFILL_STATUS_APPROVED) {
            return `${base} approved`;
        }

        if (status === AUTOFILL_STATUS_REJECTED) {
            return `${base} rejected`;
        }

        if (this.isDraftStatus(status)) {
            return `${base} direct`;
        }

        return `${base} default`;
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '';
        }

        const numericValue = Number(value);

        if (Number.isNaN(numericValue)) {
            return String(value);
        }

        return new Intl.NumberFormat(undefined, {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(numericValue);
    }

    formatConfidenceValue(value) {
        if (value === null || value === undefined || value === '') {
            return '';
        }

        const numericValue = Number(value);

        if (Number.isNaN(numericValue)) {
            return String(value);
        }

        return numericValue <= 1
            ? `${Math.round(numericValue * 100)}%`
            : `${Math.round(numericValue)}%`;
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }

        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'Something went wrong while sending the request.';
    }
}