import { api, LightningElement } from 'lwc';
import getState from '@salesforce/apex/DATLoadActionController.getState';
import postLoad from '@salesforce/apex/DATLoadActionController.postLoad';
import updateLoad from '@salesforce/apex/DATLoadActionController.updateLoad';
import deleteLoad from '@salesforce/apex/DATLoadActionController.deleteLoad';
import LightningConfirm from 'lightning/confirm';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class DatLoadAction extends LightningElement {
    _recordId;
    initialized = false;
    isLoading = true;
    errorMessage;
    state = {
        configured: false,
        authorized: false,
        environmentLabel: 'Loading',
        canPost: false,
        canUpdate: false,
        canDelete: false
    };

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value && !this.initialized) {
            this.initialized = true;
            this.loadState();
        }
    }

    get postDisabled() {
        return this.isLoading || !this.state.canPost;
    }

    get updateDisabled() {
        return this.isLoading || !this.state.canUpdate;
    }

    get deleteDisabled() {
        return this.isLoading || !this.state.canDelete;
    }

    async loadState() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.state = await getState({ recordId: this.recordId });
        } catch (error) {
            this.errorMessage = this.messageFrom(error);
        } finally {
            this.isLoading = false;
        }
    }

    async post() {
        await this.runOperation(postLoad, 'Posted');
    }

    async updatePosting() {
        await this.runOperation(updateLoad, 'Updated');
    }

    async deletePosting() {
        const confirmed = await LightningConfirm.open({
            label: 'Delete DAT posting',
            message: 'Delete this DAT posting? This cannot be undone.',
            theme: 'warning'
        });
        if (confirmed) {
            await this.runOperation(deleteLoad, 'Deleted');
        }
    }

    async runOperation(apexMethod, title) {
        if (this.isLoading) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const result = await apexMethod({ recordId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message: result.message,
                    variant: 'success'
                })
            );
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.loadState();
        } catch (error) {
            const message = this.messageFrom(error);
            this.errorMessage = message;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'DAT action failed',
                    message,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
            this.isLoading = false;
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    messageFrom(error) {
        return error?.body?.message || error?.message || 'DAT operation failed.';
    }
}
