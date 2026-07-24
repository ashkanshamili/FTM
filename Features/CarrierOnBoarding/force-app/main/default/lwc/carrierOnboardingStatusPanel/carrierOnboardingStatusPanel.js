import { LightningElement, api } from 'lwc';

import CARRIER_OBJECT
    from '@salesforce/schema/FreightTM__Carrier__c';

import ONBOARDING_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.FreightTM__On_boarding_Status__c';
import READY_FOR_LOADS
    from '@salesforce/schema/FreightTM__Carrier__c.Ready_for_Loads__c';
import LOAD_BOARD_ACTIVE
    from '@salesforce/schema/FreightTM__Carrier__c.Load_Board_Active__c';
import PUBLIC_ONBOARDING_ACCESS
    from '@salesforce/schema/FreightTM__Carrier__c.Public_Onboarding_Access__c';

import AGREEMENT_SIGNED_BY
    from '@salesforce/schema/FreightTM__Carrier__c.Agreement_Signed_By__c';
import AGREEMENT_SIGNED_DATE
    from '@salesforce/schema/FreightTM__Carrier__c.Agreement_Signed_Date__c';
import ONBOARDING_SUBMITTED_DATE
    from '@salesforce/schema/FreightTM__Carrier__c.Onboarding_Submitted_Date__c';
import AGREEMENT_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.Agreement_Status__c';
import OVERALL_COMPLIANCE_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.Overall_Compliance_Status__c';

import W9_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.W9_Status__c';
import W9_FILE_UPLOADED
    from '@salesforce/schema/FreightTM__Carrier__c.W_9_File_Uploaded__c';
import MC_AUTHORITY_FILE_UPLOADED
    from '@salesforce/schema/FreightTM__Carrier__c.MC_Authority_File_Uploaded__c';
import MC_AUTHORITY_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.MC_Authority_Status__c';
import COI_FILE_UPLOADED
    from '@salesforce/schema/FreightTM__Carrier__c.Certificate_of_Insurance_File_Uploaded__c';
import BROKER_AGREEMENT_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.Broker_Carrier_Agreement_Status__c';
import AGREEMENT_FILE_UPLOADED
    from '@salesforce/schema/FreightTM__Carrier__c.Agreement_File_Uploaded__c';
import INSURANCE_COI_STATUS
    from '@salesforce/schema/FreightTM__Carrier__c.Insurance_COI_Status__c';
import SIGNATURE_FILE_UPLOADED
    from '@salesforce/schema/FreightTM__Carrier__c.Signature_File_Uploaded__c';

export default class CarrierOnboardingStatusPanel
    extends LightningElement {

    @api recordId;

    carrierObject = CARRIER_OBJECT;

    fields = [
        ONBOARDING_STATUS,
        W9_STATUS,

        READY_FOR_LOADS,
        W9_FILE_UPLOADED,

        LOAD_BOARD_ACTIVE,
        MC_AUTHORITY_FILE_UPLOADED,

        PUBLIC_ONBOARDING_ACCESS,
        MC_AUTHORITY_STATUS,

        AGREEMENT_SIGNED_BY,
        COI_FILE_UPLOADED,

        AGREEMENT_SIGNED_DATE,
        BROKER_AGREEMENT_STATUS,

        ONBOARDING_SUBMITTED_DATE,
        AGREEMENT_FILE_UPLOADED,

        AGREEMENT_STATUS,
        INSURANCE_COI_STATUS,

        OVERALL_COMPLIANCE_STATUS,
        SIGNATURE_FILE_UPLOADED
    ];
}
