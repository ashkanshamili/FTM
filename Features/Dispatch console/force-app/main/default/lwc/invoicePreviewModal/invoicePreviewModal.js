import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import saveInvoicePdfToLoad from '@salesforce/apex/DispatchConsoleController.saveInvoicePdfToLoad';

export default class InvoicePreviewModal extends LightningModal {
    @api loadId;
    @api loadName;

    @track isSaving = false;

    get modalTitle() {
        return this.loadName
            ? `Invoice Preview - ${this.loadName}`
            : 'Invoice Preview';
    }

    get previewUrl() {
        return this.loadId
            ? `/apex/Invoice?id=${encodeURIComponent(this.loadId)}`
            : '';
    }

    get sendButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Send';
    }

    get sendDisabled() {
        return !this.loadId || this.isSaving;
    }

    handleCancel() {
        this.close({
            action: 'cancel'
        });
    }

    async handleSend() {
        if (!this.loadId) {
            return;
        }

        this.isSaving = true;

        try {
            const contentDocumentId = await saveInvoicePdfToLoad({
                loadId: this.loadId
            });

            this.close({
                action: 'saved',
                contentDocumentId
            });
        } catch (error) {
            this.close({
                action: 'error',
                message:
                    error?.body?.message ||
                    error?.message ||
                    'Unable to save invoice PDF.'
            });
        } finally {
            this.isSaving = false;
        }
    }
}