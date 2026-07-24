import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import pingDriver from '@salesforce/apex/DispatchConsoleController.pingDriver';

export default class PingDriverModal extends LightningModal {
    @api loadId;
    @api loadName;
    @api driverId;
    @api driverName;
    @api driverPhone;
    @api driverCarrier;
    @api portalLink;

    @track selectedDriverId;
    @track phoneNumber = '';
    @track selectedCarrier = '';
    @track isSending = false;
    @track errorMessage = '';

    connectedCallback() {
        this.selectedDriverId = this.driverId || null;
        this.phoneNumber = this.driverPhone || '';
        this.selectedCarrier = this.driverCarrier || '';
    }

    get modalTitle() {
        return this.loadName
            ? `Ping Driver - ${this.loadName}`
            : 'Ping Driver';
    }

    get carrierOptions() {
        return [
            { label: 'AT&T', value: 'AT&T' },
            { label: 'Verizon', value: 'Verizon' },
            { label: 'T-Mobile', value: 'T-Mobile' },
            { label: 'Sprint', value: 'Sprint' },
            { label: 'MetroPCS', value: 'MetroPCS' },
            { label: 'Boost Mobile', value: 'Boost Mobile' },
            { label: 'Cricket Wireless', value: 'Cricket Wireless' },
            { label: 'U.S. Cellular', value: 'U.S. Cellular' },
            { label: 'TracFone', value: 'TracFone' },
            { label: 'Virgin Mobile', value: 'Virgin Mobile' }
        ];
    }

    get driverDisplayInfo() {
        return {
            primaryField: 'Name',
            additionalFields: [
                'FreightTM__Phone__c'
            ]
        };
    }

    get driverMatchingInfo() {
        return {
            primaryField: {
                fieldPath: 'Name',
                mode: 'contains'
            },
            additionalFields: [
                {
                    fieldPath: 'FreightTM__Phone__c',
                    mode: 'contains'
                }
            ]
        };
    }

    get messagePreview() {
        return this.portalLink ||
            'The driver portal link will appear here.';
    }

    get sendButtonLabel() {
        return this.isSending
            ? 'Sending...'
            : 'Send';
    }

    get sendDisabled() {
        return (
            this.isSending ||
            !this.loadId ||
            !this.selectedDriverId ||
            !this.phoneNumber ||
            !this.selectedCarrier ||
            !this.portalLink
        );
    }

    handleDriverChange(event) {
        this.selectedDriverId = event.detail.recordId;
        this.errorMessage = '';
    }

    handlePhoneChange(event) {
        this.phoneNumber = event.target.value || '';
        this.errorMessage = '';
    }

    handleCarrierChange(event) {
        this.selectedCarrier = event.detail.value || '';
        this.errorMessage = '';
    }

    handleCancel() {
        this.close({
            action: 'cancel'
        });
    }

    validateInputs() {
        const inputs = [
            ...this.template.querySelectorAll(
                'lightning-input, lightning-combobox, lightning-record-picker'
            )
        ];

        return inputs.reduce((isValid, input) => {
            input.reportValidity();
            return isValid && input.checkValidity();
        }, true);
    }

    async handleSend() {
        this.errorMessage = '';

        if (!this.validateInputs()) {
            return;
        }

        if (!this.portalLink) {
            this.errorMessage =
                'The Driver Portal Link is blank for this Load.';
            return;
        }

        this.isSending = true;

        try {
            await pingDriver({
                loadId: this.loadId,
                driverId: this.selectedDriverId,
                phoneNumber: this.phoneNumber,
                carrier: this.selectedCarrier
            });

            this.close({
                action: 'sent',
                phoneNumber: this.phoneNumber
            });
        } catch (error) {
            this.errorMessage =
                error?.body?.message ||
                error?.message ||
                'Unable to send the driver portal link.';
        } finally {
            this.isSending = false;
        }
    }
}