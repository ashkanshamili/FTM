import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';

import generateOrRefresh from '@salesforce/apex/DriverPortalLinkAdminController.generateOrRefresh';

import LOAD_OBJECT from '@salesforce/schema/FreightTM__Load__c';
import DRIVER from '@salesforce/schema/FreightTM__Load__c.FreightTM__Driver__c';
import TOKEN_HASH from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Token_Hash__c';
import PORTAL_LINK from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Link__c';
import PORTAL_ACTIVE from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Active__c';
import SHIPPING_SIGNATURE from '@salesforce/schema/FreightTM__Load__c.At_Shipping_Signature__c';
import RECEIVING_SIGNATURE from '@salesforce/schema/FreightTM__Load__c.At_Receiving_Signature__c';
import IN_TRANSIT_SIGNATURE from '@salesforce/schema/FreightTM__Load__c.In_Transit_to_Delivery_Signature__c';
import DELIVERED_SIGNATURE from '@salesforce/schema/FreightTM__Load__c.Delivered_Signature__c';
import PORTAL_UPDATE from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Update__c';
import EXPIRES_AT from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Expires_At__c';
import LAST_OPENED from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Last_Opened__c';
import LAST_DEVICE from '@salesforce/schema/FreightTM__Load__c.Driver_Portal_Last_Device__c';

const STATUS_FIELDS = [DRIVER, PORTAL_LINK];

export default class DriverPortalAdminPanel extends LightningElement {
    @api recordId;

    objectApiName = LOAD_OBJECT;
    isBusy = false;
    recordData;

    fields = [
        DRIVER,
        TOKEN_HASH,
        PORTAL_UPDATE,
        PORTAL_LINK,
        EXPIRES_AT,
        PORTAL_ACTIVE,
        LAST_OPENED,
        SHIPPING_SIGNATURE,
        LAST_DEVICE,
        RECEIVING_SIGNATURE,
        IN_TRANSIT_SIGNATURE,
        DELIVERED_SIGNATURE
    ];

    @wire(getRecord, {
        recordId: '$recordId',
        fields: STATUS_FIELDS
    })
    wiredRecord({ data }) {
        if (data) {
            this.recordData = data;
        }
    }

    get hasDriver() {
        return Boolean(getFieldValue(this.recordData, DRIVER));
    }

    get portalLink() {
        return getFieldValue(this.recordData, PORTAL_LINK);
    }

    get generateButtonLabel() {
        return this.portalLink
            ? 'Refresh Driver Portal Link'
            : 'Generate Driver Portal Link';
    }

    get copyDisabled() {
        return this.isBusy || !this.portalLink;
    }

    async handleGenerate() {
        if (!this.recordId) {
            this.showToast(
                'Driver Portal',
                'The Load record could not be identified.',
                'error'
            );
            return;
        }

        if (!this.hasDriver) {
            this.showToast(
                'Driver required',
                'Select a Driver on the Load and save before generating the link.',
                'error'
            );
            return;
        }

        this.isBusy = true;

        try {
            const response = await generateOrRefresh({
                loadId: this.recordId
            });

            await notifyRecordUpdateAvailable([
                { recordId: this.recordId }
            ]);

            this.showToast(
                'Driver Portal link ready',
                response?.portalLink || 'The secure link was generated.',
                'success'
            );

            window.setTimeout(() => {
                window.location.reload();
            }, 700);
        } catch (error) {
            this.showToast(
                'Could not generate the link',
                this.reduceError(error),
                'error'
            );
        } finally {
            this.isBusy = false;
        }
    }

    async handleCopy() {
        if (!this.portalLink) {
            return;
        }

        try {
            await navigator.clipboard.writeText(this.portalLink);
            this.showToast(
                'Copied',
                'Driver Portal link copied to the clipboard.',
                'success'
            );
        } catch (error) {
            this.showToast(
                'Copy failed',
                this.reduceError(error),
                'error'
            );
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.'
        );
    }
}
