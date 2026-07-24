import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

import approveAutoFillLoad from '@salesforce/apex/AutoFillController.approveAutoFillLoad';
import rejectAutoFillLoad from '@salesforce/apex/AutoFillController.rejectAutoFillLoad';
import getExtractedDocument from '@salesforce/apex/AutoFillController.getExtractedDocument';

import STATUS_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Status__c';
import CREATED_BY_AUTOFILL_FIELD from '@salesforce/schema/FreightTM__Load__c.Created_By_AutoFill__c';
import ITEM_ID_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Item_Id__c';
import DOCUMENT_TYPE_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Document_Type__c';
import CONFIDENCE_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Confidence__c';
import EXTRACTED_JSON_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Extracted_Fields_JSON__c';
import APPROVED_AT_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Approved_At__c';
import AUTOFILL_SOURCE_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Source__c';
import RAW_RESPONSE_FIELD from '@salesforce/schema/FreightTM__Load__c.AutoFill_Raw_Response__c';

const FIELDS = [
    STATUS_FIELD,
    CREATED_BY_AUTOFILL_FIELD,
    ITEM_ID_FIELD,
    DOCUMENT_TYPE_FIELD,
    CONFIDENCE_FIELD,
    EXTRACTED_JSON_FIELD,
    APPROVED_AT_FIELD,
    AUTOFILL_SOURCE_FIELD,
    RAW_RESPONSE_FIELD
];

const STATUS_DIRECT = 'Direct';
const STATUS_DRAFT = 'Draft';
const STATUS_APPROVED = 'Approved';
const STATUS_REJECTED = 'Rejected';

export default class AutoFillLoadStatusPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    wiredRecord;
    loadError = '';
    isSaving = false;
    isLoadingDocument = false;
    extractRows = [];

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLoad(result) {
        this.wiredRecord = result;
        const { data, error } = result;

        if (data) {
            this.loadError = '';
            this.extractRows = this.rowsFromStoredJson;
            this.loadDocumentDetail();
        } else if (error) {
            this.loadError = this.getErrorMessage(error);
        }
    }

    get record() {
        return this.wiredRecord?.data;
    }

    get hasRecord() {
        return Boolean(this.record);
    }

    get isLoading() {
        return this.isSaving || this.isLoadingDocument;
    }

    get statusLabel() {
        return getFieldValue(this.record, STATUS_FIELD) || 'Not AutoFill';
    }

    get createdByAutoFill() {
        return getFieldValue(this.record, CREATED_BY_AUTOFILL_FIELD) === true;
    }

    get createdByAutoFillLabel() {
        return this.createdByAutoFill ? 'Yes' : 'No';
    }

    get sourceLabel() {
        const storedSource = getFieldValue(this.record, AUTOFILL_SOURCE_FIELD);
        let rawSource = storedSource;

        if (!rawSource) {
            const parsed = this.parseJson(
                getFieldValue(this.record, RAW_RESPONSE_FIELD) || ''
            );
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

    get sourceIcon() {
        if (this.sourceLabel === 'Email') {
            return 'utility:email';
        }

        if (this.sourceLabel === 'Manual Upload') {
            return 'utility:upload';
        }

        if (this.sourceLabel === 'API Upload') {
            return 'utility:connected_apps';
        }

        return 'utility:question';
    }

    get itemId() {
        return getFieldValue(this.record, ITEM_ID_FIELD) || '';
    }

    get documentType() {
        return getFieldValue(this.record, DOCUMENT_TYPE_FIELD) || '';
    }

    get confidence() {
        return getFieldValue(this.record, CONFIDENCE_FIELD);
    }

    get formattedConfidence() {
        if (this.confidence === null || this.confidence === undefined || this.confidence === '') {
            return '';
        }

        const numeric = Number(this.confidence);
        return Number.isNaN(numeric) ? String(this.confidence) : `${Math.round(numeric)}%`;
    }

    get approvedAt() {
        const value = getFieldValue(this.record, APPROVED_AT_FIELD);

        if (!value) {
            return '';
        }

        const date = new Date(value);
        return Number.isNaN(date.getTime())
            ? value
            : new Intl.DateTimeFormat(undefined, {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit'
            }).format(date);
    }

    get storedJson() {
        return getFieldValue(this.record, EXTRACTED_JSON_FIELD) || '';
    }

    get rowsFromStoredJson() {
        const parsed = this.parseJson(this.storedJson);
        return parsed ? this.objectToRows(parsed) : [];
    }


    get hasExtractRows() {
        return this.extractRows && this.extractRows.length > 0;
    }

    get isDirect() {
        return this.statusLabel === STATUS_DIRECT;
    }

    get isDraft() {
        return this.statusLabel === STATUS_DRAFT;
    }

    get isApproved() {
        return this.statusLabel === STATUS_APPROVED;
    }

    get isRejected() {
        return this.statusLabel === STATUS_REJECTED;
    }

    get showActions() {
        return this.createdByAutoFill && (this.isDraft || this.isDirect);
    }

    get actionDisabled() {
        return this.isSaving || !this.showActions;
    }

    get statusClass() {
        const base = 'status-pill';

        if (this.isApproved) {
            return `${base} approved`;
        }

        if (this.isRejected) {
            return `${base} rejected`;
        }

        if (this.isDirect) {
            return `${base} direct`;
        }

        return `${base} default`;
    }

    async loadDocumentDetail() {
        if (!this.itemId || this.isLoadingDocument) {
            return;
        }

        this.isLoadingDocument = true;

        try {
            const detail = await getExtractedDocument({ itemId: this.itemId });

            if (detail?.extractedFields?.length) {
                this.extractRows = this.normalizeFieldRows(detail.extractedFields);
            } else if (detail?.rawJson) {
                const parsed = this.parseJson(detail.rawJson);
                const extracted = parsed ? this.findNestedValue(parsed, ['ExtractedFields', 'extractedFields']) : null;
                this.extractRows = extracted ? this.objectToRows(extracted) : this.extractRows;
            }
        } catch (error) {
            // Keep the stored JSON table visible even if the live scan detail is not available.
            this.loadError = this.getErrorMessage(error);
        } finally {
            this.isLoadingDocument = false;
        }
    }

    async approveLoad() {
        this.isSaving = true;
        this.loadError = '';

        try {
            await approveAutoFillLoad({ loadId: this.recordId });
            await refreshApex(this.wiredRecord);
            this.showToast('Approved', 'AutoFill load was approved.', 'success');
        } catch (error) {
            this.loadError = this.getErrorMessage(error);
            this.showToast('Approval failed', this.loadError, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async rejectLoad() {
        this.isSaving = true;
        this.loadError = '';

        try {
            await rejectAutoFillLoad({ loadId: this.recordId });
            this.showToast('Rejected', 'AutoFill load was rejected and deleted.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'FreightTM__Load__c',
                    actionName: 'list'
                }
            });
        } catch (error) {
            this.loadError = this.getErrorMessage(error);
            this.showToast('Reject failed', this.loadError, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    normalizeFieldRows(rows) {
        return rows
            .filter((row) => row)
            .map((row, index) => ({
                id: `${row.fieldName || 'field'}-${index}`,
                label: this.formatFieldLabel(row.fieldName || ''),
                displayValue: this.formatDisplayValue(row.value)
            }))
            .filter((row) => row.label || row.displayValue);
    }

    objectToRows(source, prefix = '') {
        if (!source || typeof source !== 'object') {
            return [];
        }

        if (Array.isArray(source)) {
            return source.map((value, index) => ({
                id: `${prefix || 'Item'}-${index}`,
                label: this.formatFieldLabel(`${prefix || 'Item'} ${index + 1}`),
                displayValue: this.formatDisplayValue(value)
            }));
        }

        return Object.keys(source)
            .sort()
            .flatMap((key) => {
                const value = source[key];
                const fullKey = prefix ? `${prefix}.${key}` : key;

                if (value && typeof value === 'object' && !Array.isArray(value)) {
                    return this.objectToRows(value, fullKey);
                }

                return [{
                    id: fullKey,
                    label: this.formatFieldLabel(fullKey),
                    displayValue: this.formatDisplayValue(value)
                }];
            })
            .filter((row) => row.displayValue !== '');
    }

    parseJson(value) {
        if (!value) {
            return null;
        }

        try {
            return typeof value === 'string' ? JSON.parse(value) : value;
        } catch (error) {
            return null;
        }
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

        for (const value of Object.values(source)) {
            if (value && typeof value === 'object' && !Array.isArray(value)) {
                const nested = this.findNestedValue(value, possibleKeys);

                if (nested !== undefined && nested !== null) {
                    return nested;
                }
            }
        }

        return undefined;
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

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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

        return 'Something went wrong.';
    }
}