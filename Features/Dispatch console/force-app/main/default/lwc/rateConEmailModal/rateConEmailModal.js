import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import sendRateConEmailToCarrier from '@salesforce/apex/DispatchConsoleController.sendRateConEmailToCarrier';

export default class RateConEmailModal extends LightningModal {
    @api loadId;
    @api loadName;
    @api carrierName;
    @api carrierEmail;

    @track toEmail = '';
    @track subject = '';
    @track body = '';
    @track isSending = false;

    connectedCallback() {
        this.toEmail = this.carrierEmail || '';
        this.subject = `Rate Confirmation for Load ${this.loadName || ''}`;
        this.body = this.carrierName
            ? `Dear ${this.carrierName},\n\nPlease find the rate confirmation attached.\n\nThank you.`
            : 'Please find the rate confirmation attached.';
    }

    get modalTitle() {
        return this.loadName
            ? `Email RateCon - ${this.loadName}`
            : 'Email RateCon';
    }

    get previewUrl() {
        return this.loadId
            ? `/apex/RateCon?id=${encodeURIComponent(this.loadId)}`
            : '';
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending...' : 'Send';
    }

    get sendDisabled() {
        return !this.loadId || !this.toEmail || this.isSending;
    }

    handleEmailChange(event) {
        this.toEmail = event.target.value || '';
    }

    handleSubjectChange(event) {
        this.subject = event.target.value || '';
    }

    handleBodyChange(event) {
        this.body = event.target.value || '';
    }

    handleCancel() {
        this.close({
            action: 'cancel'
        });
    }

    async handleSend() {
        if (!this.loadId || !this.toEmail) {
            return;
        }

        this.isSending = true;

        try {
            await sendRateConEmailToCarrier({
                loadId: this.loadId,
                toEmail: this.toEmail,
                subject: this.subject,
                body: this.body
            });

            this.close({
                action: 'sent'
            });
        } catch (error) {
            this.close({
                action: 'error',
                message:
                    error?.body?.message ||
                    error?.message ||
                    'Unable to send RateCon email.'
            });
        } finally {
            this.isSending = false;
        }
    }
}