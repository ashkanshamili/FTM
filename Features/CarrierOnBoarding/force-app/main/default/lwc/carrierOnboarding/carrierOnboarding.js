import { LightningElement, track } from 'lwc';
import FTMLogo from '@salesforce/resourceUrl/FTM_Logo';
import Agreement from '@salesforce/resourceUrl/Carrier_Agreement';

import saveCarrier from '@salesforce/apex/CarrierOnboardingController.saveCarrier';
import uploadCarrierDocument from '@salesforce/apex/CarrierOnboardingController.uploadCarrierDocument';
import submitForReview from '@salesforce/apex/CarrierOnboardingController.submitForReview';

export default class CarrierOnboarding extends LightningElement {
    @track form = {
        carrierId: null,

        carrierName: '',
        mcNumber: '',
        usdotNumber: '',
        federalId: '',
        scacCode: '',
        website: '',

        primaryContact: '',
        title: '',
        email: '',
        phone: '',
        afterHoursPhone: '',

        street: '',
        city: '',
        country: '',
        stateProvince: '',
        zipCode: '',

        billingStreet: '',
        billingCity: '',
        billingCountry: '',
        billingStateProvince: '',
        billingZipCode: '',

        mode: '',
        ltl: false,
        hazmatPermit: false,
        preferredLanes: '',
        numberOfDrivers: null,
        numberOfTractors: null,
        numberOfTrailers: null,
        onlineGpsTracking: false,

        cargoInsuranceAmount: null,
        cargoInsuranceExpiration: null,
        liabilityInsuranceAmount: null,
        liabilityInsuranceExpiration: null,

        remarks: '',

        agreementAccepted: false,
        agreementSignedBy: ''
    };

    get hollowayLogoUrl() {
        return FTMLogo;
    }

    @track showAgreementModal = false;

    get agreementDownloadUrl() {
    return Agreement;
    }

    openAgreementModal() {
    this.showAgreementModal = true;
    }

    closeAgreementModal() {
    this.showAgreementModal = false;
    }

    @track step = 1;
    @track isLoading = false;
    @track message = '';
    @track messageType = 'info';

    selectedFiles = {};
    insuranceDocExpiration = null;
    selectedModes = [];

    uploadedDocuments = {
    w9: false,
    mcAuthority: false,
    insurance: false,
    agreement: false,
    signature: false
    };

    isDrawingSignature = false;
hasSignature = false;

    modeOptions = [
        { label: 'LTL', value: 'LTL' },
        { label: 'Air Freight', value: 'Air Freight' },
        { label: 'Cargo Van', value: 'Cargo Van' },
        { label: 'Semi', value: 'Semi' }
    ];

    /*
     * Important:
     * These values must exactly match your Carrier picklist values.
     * If your Salesforce picklist uses USA instead of United States,
     * change value: 'United States' to value: 'USA'.
     */
    countryOptions = [
        { label: 'United States', value: 'United States' },
        { label: 'Canada', value: 'Canada' }
    ];

    usStateOptions = [
    { label: 'Alabama', value: 'AL' },
    { label: 'Alaska', value: 'AK' },
    { label: 'Arizona', value: 'AZ' },
    { label: 'Arkansas', value: 'AR' },
    { label: 'California', value: 'CA' },
    { label: 'Colorado', value: 'CO' },
    { label: 'Connecticut', value: 'CT' },
    { label: 'Delaware', value: 'DE' },
    { label: 'Florida', value: 'FL' },
    { label: 'Georgia', value: 'GA' },
    { label: 'Hawaii', value: 'HI' },
    { label: 'Idaho', value: 'ID' },
    { label: 'Illinois', value: 'IL' },
    { label: 'Indiana', value: 'IN' },
    { label: 'Iowa', value: 'IA' },
    { label: 'Kansas', value: 'KS' },
    { label: 'Kentucky', value: 'KY' },
    { label: 'Louisiana', value: 'LA' },
    { label: 'Maine', value: 'ME' },
    { label: 'Maryland', value: 'MD' },
    { label: 'Massachusetts', value: 'MA' },
    { label: 'Michigan', value: 'MI' },
    { label: 'Minnesota', value: 'MN' },
    { label: 'Mississippi', value: 'MS' },
    { label: 'Missouri', value: 'MO' },
    { label: 'Montana', value: 'MT' },
    { label: 'Nebraska', value: 'NE' },
    { label: 'Nevada', value: 'NV' },
    { label: 'New Hampshire', value: 'NH' },
    { label: 'New Jersey', value: 'NJ' },
    { label: 'New Mexico', value: 'NM' },
    { label: 'New York', value: 'NY' },
    { label: 'North Carolina', value: 'NC' },
    { label: 'North Dakota', value: 'ND' },
    { label: 'Ohio', value: 'OH' },
    { label: 'Oklahoma', value: 'OK' },
    { label: 'Oregon', value: 'OR' },
    { label: 'Pennsylvania', value: 'PA' },
    { label: 'Rhode Island', value: 'RI' },
    { label: 'South Carolina', value: 'SC' },
    { label: 'South Dakota', value: 'SD' },
    { label: 'Tennessee', value: 'TN' },
    { label: 'Texas', value: 'TX' },
    { label: 'Utah', value: 'UT' },
    { label: 'Vermont', value: 'VT' },
    { label: 'Virginia', value: 'VA' },
    { label: 'Washington', value: 'WA' },
    { label: 'West Virginia', value: 'WV' },
    { label: 'Wisconsin', value: 'WI' },
    { label: 'Wyoming', value: 'WY' }
];

canadaProvinceOptions = [
    { label: 'Alberta', value: 'AB' },
    { label: 'British Columbia', value: 'BC' },
    { label: 'Manitoba', value: 'MB' },
    { label: 'New Brunswick', value: 'NB' },
    { label: 'Newfoundland and Labrador', value: 'NL' },
    { label: 'Northwest Territories', value: 'NT' },
    { label: 'Nova Scotia', value: 'NS' },
    { label: 'Nunavut', value: 'NU' },
    { label: 'Ontario', value: 'ON' },
    { label: 'Prince Edward Island', value: 'PE' },
    { label: 'Quebec', value: 'QC' },
    { label: 'Saskatchewan', value: 'SK' },
    { label: 'Yukon', value: 'YT' }
];

    get physicalStateOptions() {
    if (this.form.country === 'Canada') {
        return this.canadaProvinceOptions;
    }

    if (this.form.country === 'United States') {
        return this.usStateOptions;
    }

    return [];
}

get billingStateOptions() {
    if (this.form.billingCountry === 'Canada') {
        return this.canadaProvinceOptions;
    }

    if (
        this.form.billingCountry ===
        'United States'
    ) {
        return this.usStateOptions;
    }

    return [];
}

get disablePhysicalState() {
    return !this.form.country;
}

get disableBillingState() {
    return !this.form.billingCountry;
}

    get showStep1() {
        return this.step === 1;
    }

    get showStep2() {
        return this.step === 2;
    }

    get showStep3() {
        return this.step === 3;
    }

    get messageClass() {
        return `message ${this.messageType}`;
    }

    handleInput(event) {
    const field =
        event.target.dataset.field;

    if (!field) {
        return;
    }

    const value =
        event.target.value;

    const updatedForm = {
        ...this.form,
        [field]: value
    };

    if (field === 'country') {
        updatedForm.stateProvince = '';
    }

    if (field === 'billingCountry') {
        updatedForm.billingStateProvince = '';
    }

    this.form =
        updatedForm;
}

    handleCheckbox(event) {
    const field = event.target.dataset.field;

    if (!field) {
        return;
    }

    this.form = {
        ...this.form,
        [field]: event.target.checked
    };
}

    handleModeChange(event) {
    this.selectedModes = event.detail.value;
    this.form = {
        ...this.form,
        mode: this.selectedModes.join(';')
    };
}

    handleInsuranceDocExpiration(event) {
        this.insuranceDocExpiration = event.target.value;
    }

    async saveAndContinue() {
    this.clearMessage();

    this.syncFormFromInputs();

    if (!this.validateStep1()) {
        return;
    }

    this.isLoading = true;

    try {
        const carrierInput =
            this.buildCarrierInput();

        console.log(
            'Carrier input:',
            JSON.stringify(carrierInput)
        );

        const result =
            await saveCarrier({
                input: carrierInput
            });

        if (result?.success) {
            this.form = {
                ...this.form,
                carrierId:
                    result.carrierId
            };

            this.showSuccess(
                result.message ||
                'Carrier information saved.'
            );

            this.step = 2;

        } else {
            this.showError(
                result?.message ||
                'Carrier information could not be saved.'
            );
        }

    } catch (error) {
        console.error(
            'saveCarrier error:',
            JSON.stringify(error)
        );

        this.showError(
            this.reduceError(error)
        );

    } finally {
        this.isLoading = false;
    }
}
buildCarrierInput() {
    return {
        carrierId:
            this.nullIfBlank(
                this.form.carrierId
            ),

        carrierName:
            this.trimOrNull(
                this.form.carrierName
            ),

        mcNumber:
            this.trimOrNull(
                this.form.mcNumber
            ),

        usdotNumber:
            this.trimOrNull(
                this.form.usdotNumber
            ),

        federalId:
            this.trimOrNull(
                this.form.federalId
            ),

        scacCode:
            this.trimOrNull(
                this.form.scacCode
            ),

        website:
            this.trimOrNull(
                this.form.website
            ),

        primaryContact:
            this.trimOrNull(
                this.form.primaryContact
            ),

        title:
            this.trimOrNull(
                this.form.title
            ),

        email:
            this.trimOrNull(
                this.form.email
            ),

        phone:
            this.trimOrNull(
                this.form.phone
            ),

        afterHoursPhone:
            this.trimOrNull(
                this.form.afterHoursPhone
            ),

        street:
            this.trimOrNull(
                this.form.street
            ),

        city:
            this.trimOrNull(
                this.form.city
            ),

        country:
            this.trimOrNull(
                this.form.country
            ),

        stateProvince:
            this.trimOrNull(
                this.form.stateProvince
            ),

        zipCode:
            this.trimOrNull(
                this.form.zipCode
            ),

        billingStreet:
            this.trimOrNull(
                this.form.billingStreet
            ),

        billingCity:
            this.trimOrNull(
                this.form.billingCity
            ),

        billingCountry:
            this.trimOrNull(
                this.form.billingCountry
            ),

        billingStateProvince:
            this.trimOrNull(
                this.form.billingStateProvince
            ),

        billingZipCode:
            this.trimOrNull(
                this.form.billingZipCode
            ),

        mode:
            this.trimOrNull(
                this.selectedModes.join(';')
            ),

        ltl:
            Boolean(
                this.form.ltl
            ),

        hazmatPermit:
            Boolean(
                this.form.hazmatPermit
            ),

        preferredLanes:
            this.trimOrNull(
                this.form.preferredLanes
            ),

        numberOfDrivers:
            this.numberOrNull(
                this.form.numberOfDrivers
            ),

        numberOfTractors:
            this.numberOrNull(
                this.form.numberOfTractors
            ),

        numberOfTrailers:
            this.numberOrNull(
                this.form.numberOfTrailers
            ),

        onlineGpsTracking:
            Boolean(
                this.form.onlineGpsTracking
            ),

        cargoInsuranceAmount:
            this.numberOrNull(
                this.form.cargoInsuranceAmount
            ),

        cargoInsuranceExpiration:
            this.dateOrNull(
                this.form.cargoInsuranceExpiration
            ),

        liabilityInsuranceAmount:
            this.numberOrNull(
                this.form.liabilityInsuranceAmount
            ),

        liabilityInsuranceExpiration:
            this.dateOrNull(
                this.form.liabilityInsuranceExpiration
            ),

        remarks:
            this.trimOrNull(
                this.form.remarks
            ),

        agreementAccepted:
            Boolean(
                this.form.agreementAccepted
            ),

        agreementSignedBy:
            this.trimOrNull(
                this.form.agreementSignedBy
            )
    };
}
trimOrNull(value) {
    if (
        value === null ||
        value === undefined
    ) {
        return null;
    }

    const normalized =
        String(value).trim();

    return normalized === ''
        ? null
        : normalized;
}

nullIfBlank(value) {
    return this.trimOrNull(value);
}

numberOrNull(value) {
    if (
        value === null ||
        value === undefined ||
        String(value).trim() === ''
    ) {
        return null;
    }

    const numericValue =
        Number(value);

    return Number.isFinite(numericValue)
        ? numericValue
        : null;
}

dateOrNull(value) {
    if (
        value === null ||
        value === undefined ||
        String(value).trim() === ''
    ) {
        return null;
    }

    /*
     * lightning-input type="date" provides YYYY-MM-DD,
     * which Apex Date can deserialize.
     */
    return String(value).trim();
}
    /*async saveAndContinue() {
    this.clearMessage();

    this.syncFormFromInputs();

    if (!this.validateStep1()) {
        return;
    }

    this.isLoading = true;

    try {
        const result = await saveCarrier({
            input: this.form
        });

        if (result.success) {
            this.form.carrierId = result.carrierId;
            this.showSuccess(result.message);
            this.step = 2;
        } else {
            this.showError(result.message);
        }
    } catch (error) {
        console.error('saveCarrier error', JSON.stringify(error));
        this.showError(this.reduceError(error));
    } finally {
        this.isLoading = false;
    }
}
*/
   /* syncFormFromInputs() {
    const inputs = this.template.querySelectorAll(
        'lightning-input, lightning-textarea, lightning-combobox'
    );

    inputs.forEach((input) => {
        const field = input.dataset.field;

        if (!field) {
            return;
        }

        if (input.type === 'checkbox') {
            this.form[field] = input.checked;
        } else {
            this.form[field] = input.value;
        }
    });

    this.form.mode = this.selectedModes.join(';');
}*/
syncFormFromInputs() {
    const controls =
        this.template.querySelectorAll(
            'lightning-input, ' +
            'lightning-textarea, ' +
            'lightning-combobox'
        );

    const updatedForm = {
        ...this.form
    };

    controls.forEach((control) => {
        const field =
            control.dataset.field;

        if (!field) {
            return;
        }

        if (
            control.type ===
            'checkbox'
        ) {
            updatedForm[field] =
                Boolean(
                    control.checked
                );

        } else {
            updatedForm[field] =
                control.value;
        }
    });

    updatedForm.mode =
        this.selectedModes.join(';');

    this.form =
        updatedForm;
}

    handleFileSelected(event) {
        const documentType = event.target.dataset.type;
        const file = event.target.files[0];

        if (!file) {
            return;
        }

        const maxSize = 4500000;

        if (file.size > maxSize) {
            this.showError('File is too large. Please upload a file under 4.5 MB.');
            return;
        }

        this.selectedFiles[documentType] = file;
        this.showSuccess(`${file.name} selected for ${documentType}.`);
    }

    async uploadSelectedFile(event) {
        const documentType = event.target.dataset.type;
        const file = this.selectedFiles[documentType];

        this.clearMessage();

        if (!this.form.carrierId) {
            this.showError('Please save carrier information first.');
            return;
        }

        if (!file) {
            this.showError(`Please choose a file for ${documentType}.`);
            return;
        }

        this.isLoading = true;

        try {
            const base64Data = await this.fileToBase64(file);

            let expirationDate = null;
            if (documentType === 'Certificate of Insurance') {
                expirationDate = this.insuranceDocExpiration || this.form.liabilityInsuranceExpiration || this.form.cargoInsuranceExpiration;
            }

            const result = await uploadCarrierDocument({
                input: {
                    carrierId: this.form.carrierId,
                    documentType: documentType,
                    fileName: file.name,
                    base64Data: base64Data,
                    expirationDate: expirationDate
                }
            });

            if (result.success) {
    this.markDocumentUploaded(documentType);
    this.showSuccess(result.message);
} else {
    this.showError(result.message);
}
        } catch (error) {
            console.error('uploadCarrierDocument error', JSON.stringify(error));
            this.showError(this.reduceError(error));
        } finally {
            this.isLoading = false;
        }
    }

    markDocumentUploaded(documentType) {
    if (documentType === 'W-9') {
        this.uploadedDocuments = { ...this.uploadedDocuments, w9: true };
    } else if (documentType === 'MC Authority') {
        this.uploadedDocuments = { ...this.uploadedDocuments, mcAuthority: true };
    } else if (documentType === 'Certificate of Insurance') {
        this.uploadedDocuments = { ...this.uploadedDocuments, insurance: true };
    } else if (documentType === 'Broker Carrier Agreement') {
        this.uploadedDocuments = { ...this.uploadedDocuments, agreement: true };
    } else if (documentType === 'Signature') {
        this.uploadedDocuments = { ...this.uploadedDocuments, signature: true };
    }
}

    async submitReview() {
        this.clearMessage();

        if (!this.form.carrierId) {
            this.showError('Please save carrier information first.');
            return;
        }

        this.isLoading = true;

        try {
            const result = await submitForReview({
                carrierId: this.form.carrierId
            });

            if (result.success) {
                this.showSuccess(result.message);
                this.step = 3;
            } else {
                this.showError(result.message);
            }
        } catch (error) {
            console.error('submitForReview error', JSON.stringify(error));
            this.showError(this.reduceError(error));
        } finally {
            this.isLoading = false;
        }
    }

    goToStep1() {
        this.step = 1;
    }

    validateStep1() {
       this.clearMessage();

    const controls =
        this.template.querySelectorAll(
            'lightning-input, ' +
            'lightning-combobox, ' +
            'lightning-textarea, ' +
            'lightning-dual-listbox'
        );

    let allControlsValid = true;

    controls.forEach((control) => {
        if (
            typeof control.reportValidity ===
            'function'
        ) {
            control.reportValidity();
        }

        if (
            typeof control.checkValidity ===
                'function' &&
            !control.checkValidity()
        ) {
            allControlsValid = false;
        }
    });

    if (!allControlsValid) {
        this.showError(
            'Please complete all required fields before continuing.'
        );

        return false;
    }



        if (!this.form.carrierName) {
            this.showError('Carrier Name is required.');
            return false;
        }

        if (!this.form.email) {
            this.showError('Email is required.');
            return false;
        }

        if (!this.form.phone) {
            this.showError('Phone is required.');
            return false;
        }

        if (!this.form.mcNumber && !this.form.usdotNumber) {
            this.showError('Please enter either MC/MX/FF Number or USDOT Number.');
            return false;
        }

        if (this.form.scacCode && this.form.scacCode.length > 5) {
            this.showError('SCAC Code must be 5 characters or less.');
            return false;
        }

        if (this.form.mcNumber && this.form.mcNumber.length > 10) {
            this.showError('MC/MX/FF Number must be 10 characters or less.');
            return false;
        }

        if (this.form.usdotNumber && this.form.usdotNumber.length > 10) {
            this.showError('USDOT Number must be 10 characters or less.');
            return false;
        }

        if (this.form.federalId && this.form.federalId.length > 10) {
            this.showError('Federal ID must be 10 characters or less.');
            return false;
        }

        if (this.form.zipCode && this.form.zipCode.length > 10) {
            this.showError('Zip Code must be 10 characters or less.');
            return false;
        }

        if (this.form.billingZipCode && this.form.billingZipCode.length > 10) {
            this.showError('Billing Zip Code must be 10 characters or less.');
            return false;
        }

        if (!this.trimOrNull(this.form.primaryContact)) {
        this.showError(
            'Primary Contact is required.'
        );
        return false;
    }

    if (!this.trimOrNull(this.form.preferredLanes)) {
        this.showError(
            'Preferred Lanes is required.'
        );
        return false;
    }

    if (
        this.numberOrNull(
            this.form.numberOfDrivers
        ) === null
    ) {
        this.showError(
            'Number of Drivers is required.'
        );
        return false;
    }
    if (
        this.numberOrNull(
            this.form.numberOfTractors
        ) === null
    ) {
        this.showError(
            'Number of Tractors is required.'
        );
        return false;
    }

    if (
        this.numberOrNull(
            this.form.numberOfTrailers
        ) === null
    ) {
        this.showError(
            'Number of Trailers is required.'
        );
        return false;
    }

    if (
        this.numberOrNull(
            this.form.cargoInsuranceAmount
        ) === null
    ) {
        this.showError(
            'Cargo Insurance Amount is required.'
        );
        return false;
    }

    if (
        this.numberOrNull(
            this.form.cargoInsuranceAmount
        ) <= 0
    ) {
        this.showError(
            'Cargo Insurance Amount must be greater than zero.'
        );
        return false;
    }

    if (
        !this.dateOrNull(
            this.form.cargoInsuranceExpiration
        )
    ) {
        this.showError(
            'Cargo Insurance Expiration is required.'
        );
        return false;
    }

    if (
        this.numberOrNull(
            this.form.liabilityInsuranceAmount
        ) === null
    ) {
        this.showError(
            'Liability Insurance Amount is required.'
        );
        return false;
    }

        if (
        this.numberOrNull(
            this.form.liabilityInsuranceAmount
        ) <= 0
    ) {
        this.showError(
            'Liability Insurance Amount must be greater than zero.'
        );
        return false;
    }

    if (
        !this.dateOrNull(
            this.form.liabilityInsuranceExpiration
        )
    ) {
        this.showError(
            'Liability Insurance Expiration is required.'
        );
        return false;
    }

    if (
        this.form.agreementAccepted !== true
    ) {
        this.showError(
            'You must accept the broker-carrier agreement before continuing.'
        );
        return false;
    }

    if (
        !this.trimOrNull(
            this.form.agreementSignedBy
        )
    ) {
        this.showError(
            'Signed By is required before continuing.'
        );
        return false;
    }

        return true;
    }

    fileToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();

            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve(base64);
            };

            reader.onerror = () => {
                reject(new Error('Unable to read file.'));
            };

            reader.readAsDataURL(file);
        });
    }

    showSuccess(message) {
        this.messageType = 'success';
        this.message = message;
    }

    showError(message) {
        this.messageType = 'error';
        this.message = message || 'Unexpected onboarding error.';
    }

    clearMessage() {
        this.message = '';
        this.messageType = 'info';
    }

    reduceError(error) {
    console.error(
        'Carrier Onboarding error:',
        error
    );

    if (!error) {
        return 'An unknown error occurred.';
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
                .filter(Boolean);

        if (messages.length) {
            return messages.join(', ');
        }
    }

    if (
        typeof error.body ===
        'string'
    ) {
        return error.body;
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
        'The carrier information could not be submitted. ' +
        'Please review the entered values and try again.'
    );
}
/*
    reduceError(error) {
        if (!error) {
            return 'Unknown error.';
        }

        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }

        if (error.body && error.body.message) {
            return error.body.message;
        }

        if (error.message) {
            return error.message;
        }

        return JSON.stringify(error);
    }*/

    startSignature(event) {
    event.preventDefault();

    const canvas =
        this.template.querySelector(
            '.signature-canvas'
        );

    if (!canvas) {
        return;
    }

    const context =
        canvas.getContext('2d');

    const position =
        this.getSignaturePosition(
            event,
            canvas
        );

    this.isDrawingSignature = true;
    this.hasSignature = true;

    context.beginPath();

    context.moveTo(
        position.x,
        position.y
    );
}

drawSignature(event) {
    if (!this.isDrawingSignature) {
        return;
    }

    event.preventDefault();

    const canvas =
        this.template.querySelector(
            '.signature-canvas'
        );

    if (!canvas) {
        return;
    }

    const context =
        canvas.getContext('2d');

    const position =
        this.getSignaturePosition(
            event,
            canvas
        );

    context.lineWidth = 2;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.strokeStyle = '#111827';

    context.lineTo(
        position.x,
        position.y
    );

    context.stroke();
}
endSignature(event) {
    if (event) {
        event.preventDefault();
    }

    if (!this.isDrawingSignature) {
        return;
    }

    const canvas =
        this.template.querySelector(
            '.signature-canvas'
        );

    if (canvas) {
        const context =
            canvas.getContext('2d');

        context.closePath();
    }

    this.isDrawingSignature = false;
}

    /*startSignature(event) {
    event.preventDefault();

    const canvas = this.template.querySelector('.signature-canvas');
    const context = canvas.getContext('2d');
    const position = this.getSignaturePosition(event, canvas);

    this.isDrawingSignature = true;
    this.hasSignature = true;

    context.beginPath();
    context.moveTo(position.x, position.y);
}

drawSignature(event) {
    if (!this.isDrawingSignature) {
        return;
    }

    event.preventDefault();

    const canvas = this.template.querySelector('.signature-canvas');
    const context = canvas.getContext('2d');
    const position = this.getSignaturePosition(event, canvas);

    context.lineWidth = 2;
    context.lineCap = 'round';
    context.strokeStyle = '#111827';
    context.lineTo(position.x, position.y);
    context.stroke();
}

endSignature(event) {
    if (event) {
        event.preventDefault();
    }

    this.isDrawingSignature = false;
}*/

clearSignature() {
    const canvas = this.template.querySelector('.signature-canvas');

    if (!canvas) {
        return;
    }

    const context = canvas.getContext('2d');
    context.clearRect(0, 0, canvas.width, canvas.height);

    this.hasSignature = false;
    this.uploadedDocuments = {
        ...this.uploadedDocuments,
        signature: false
    };
}

/*getSignaturePosition(event, canvas) {
    const rect = canvas.getBoundingClientRect();

    let clientX;
    let clientY;

    if (event.touches && event.touches.length > 0) {
        clientX = event.touches[0].clientX;
        clientY = event.touches[0].clientY;
    } else {
        clientX = event.clientX;
        clientY = event.clientY;
    }

    return {
        x: clientX - rect.left,
        y: clientY - rect.top
    };
}*/

getSignaturePosition(event, canvas) {
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

    } else if (
        event.changedTouches &&
        event.changedTouches.length > 0
    ) {
        clientX =
            event.changedTouches[0].clientX;

        clientY =
            event.changedTouches[0].clientY;

    } else {
        clientX =
            event.clientX;

        clientY =
            event.clientY;
    }

    /*
     * Scale the browser cursor position to the
     * canvas internal coordinate system.
     */
    const scaleX =
        canvas.width / rect.width;

    const scaleY =
        canvas.height / rect.height;

    return {
        x:
            (clientX - rect.left) *
            scaleX,

        y:
            (clientY - rect.top) *
            scaleY
    };
}

async saveSignature() {
    this.clearMessage();

    if (!this.form.carrierId) {
        this.showError('Please save carrier information first.');
        return;
    }

    if (!this.hasSignature) {
        this.showError('Please draw a signature before saving.');
        return;
    }

    const canvas = this.template.querySelector('.signature-canvas');

    if (!canvas) {
        this.showError('Signature pad was not found.');
        return;
    }

    this.isLoading = true;

    try {
        const dataUrl = canvas.toDataURL('image/png');
        const base64Data = dataUrl.split(',')[1];

        const result = await uploadCarrierDocument({
            input: {
                carrierId: this.form.carrierId,
                documentType: 'Signature',
                fileName: `${this.form.carrierName || 'Carrier'} - Signature.png`,
                base64Data: base64Data,
                expirationDate: null
            }
        });

        if (result.success) {
            this.uploadedDocuments = {
                ...this.uploadedDocuments,
                signature: true
            };

            this.showSuccess(result.message);
        } else {
            this.showError(result.message);
        }
    } catch (error) {
        console.error('saveSignature error', JSON.stringify(error));
        this.showError(this.reduceError(error));
    } finally {
        this.isLoading = false;
    }
}
}

/*
sf project deploy start `
    --source-dir "force-app/main/default/lwc/carrierOnboarding" `
    --target-org "CarrierLoadBoardProduction" `
    --ignore-conflicts `
    --wait 30
    */