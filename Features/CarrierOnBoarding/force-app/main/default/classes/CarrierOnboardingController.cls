public without sharing class CarrierOnboardingController {

    // Managed Carrier On-boarding Status values used by FTM.
    // These strings must match the picklist API names exactly.
    public static final String STATUS_NEW = 'New';
    public static final String STATUS_PACKET_SENT = 'Packet Sent';
    public static final String STATUS_PAPERWORK_SIGNED = 'Paperwork Signed';
    public static final String STATUS_NOT_COMPLETE = 'Not Complete';
    public static final String STATUS_COMPLIANT = 'Compliant';
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_AGREEMENT_PENDING = 'Agreement Pending';
    public static final String STATUS_DOCUMENTS_PENDING = 'Documents Pending';
    public static final String STATUS_COMPLIANCE_REVIEW = 'Compliance Review';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String STATUS_EXPIRED_NEEDS_UPDATE = 'Expired / Needs Update';
    public static final String STATUS_READY_FOR_LOADS = 'Ready for Loads';

    public class OnboardingValidationException extends Exception {}

    public class CarrierInput {
        @AuraEnabled public Id carrierId { get; set; }

        @AuraEnabled public String carrierName { get; set; }
        @AuraEnabled public String mcNumber { get; set; }
        @AuraEnabled public String usdotNumber { get; set; }
        @AuraEnabled public String federalId { get; set; }
        @AuraEnabled public String scacCode { get; set; }
        @AuraEnabled public String website { get; set; }

        @AuraEnabled public String primaryContact { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String afterHoursPhone { get; set; }

        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String stateProvince { get; set; }
        @AuraEnabled public String zipCode { get; set; }

        @AuraEnabled public String billingStreet { get; set; }
        @AuraEnabled public String billingCity { get; set; }
        @AuraEnabled public String billingCountry { get; set; }
        @AuraEnabled public String billingStateProvince { get; set; }
        @AuraEnabled public String billingZipCode { get; set; }

        @AuraEnabled public String mode { get; set; }
        @AuraEnabled public Boolean ltl { get; set; }
        @AuraEnabled public Boolean hazmatPermit { get; set; }
        @AuraEnabled public String preferredLanes { get; set; }
        @AuraEnabled public Decimal numberOfDrivers { get; set; }
        @AuraEnabled public Decimal numberOfTractors { get; set; }
        @AuraEnabled public Decimal numberOfTrailers { get; set; }
        @AuraEnabled public Boolean onlineGpsTracking { get; set; }

        @AuraEnabled public Decimal cargoInsuranceAmount { get; set; }
        @AuraEnabled public Date cargoInsuranceExpiration { get; set; }
        @AuraEnabled public Decimal liabilityInsuranceAmount { get; set; }
        @AuraEnabled public Date liabilityInsuranceExpiration { get; set; }

        @AuraEnabled public String remarks { get; set; }

        @AuraEnabled public Boolean agreementAccepted { get; set; }
        @AuraEnabled public String agreementSignedBy { get; set; }
    }

    public class DocumentInput {
        @AuraEnabled public Id carrierId { get; set; }
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
    }

    public class OnboardingResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id carrierId { get; set; }
        @AuraEnabled public Id contentDocumentId { get; set; }
    }

    @AuraEnabled
    public static OnboardingResult saveCarrier(CarrierInput input) {
        OnboardingResult result = new OnboardingResult();

        try {
            validateCarrierInput(input);

            FreightTM__Carrier__c carrier;
            String originalOnboardingStatus;

            if (input.carrierId != null) {
                carrier = [
                    SELECT Id, FreightTM__On_boarding_Status__c
                    FROM FreightTM__Carrier__c
                    WHERE Id = :input.carrierId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                originalOnboardingStatus =
                    carrier.FreightTM__On_boarding_Status__c;
            } else {
                carrier = new FreightTM__Carrier__c();
            }

            carrier.Name = input.carrierName;
            carrier.FreightTM__MC_MX_FF_Number__c = input.mcNumber;
            carrier.FreightTM__USDOT_Number__c = input.usdotNumber;
            carrier.FreightTM__Federal_ID__c = input.federalId;
            carrier.FreightTM__SCAC_Code__c = input.scacCode;
            carrier.FreightTM__Website__c = input.website;

            carrier.FreightTM__Primary_Contact__c = input.primaryContact;
            carrier.FreightTM__Title__c = input.title;
            carrier.FreightTM__Email__c = input.email;
            carrier.FreightTM__Phone__c = input.phone;
            carrier.FreightTM__After_Hours_Phone__c = input.afterHoursPhone;

            carrier.FreightTM__Address__c = input.street;
            carrier.FreightTM__City__c = input.city;
            carrier.FreightTM__Country__c = input.country;
            carrier.FreightTM__State_Province__c = input.stateProvince;
            carrier.FreightTM__Zip_Code__c = input.zipCode;

            carrier.FreightTM__Billing_Address__c = input.billingStreet;
            carrier.FreightTM__Billing_City__c = input.billingCity;
            carrier.FreightTM__Billing_Country__c = input.billingCountry;
            carrier.FreightTM__Billing_State_Province__c = input.billingStateProvince;
            carrier.FreightTM__Billing_Zip_Code__c = input.billingZipCode;

            carrier.FreightTM__Mode__c = input.mode;
            carrier.FreightTM__LTL__c = input.ltl == true;
            carrier.FreightTM__Hazmat_Permit__c = input.hazmatPermit == true;
            carrier.FreightTM__Preferred_Lanes__c = input.preferredLanes;
            carrier.FreightTM__Number_of_Drivers__c = input.numberOfDrivers;
            carrier.FreightTM__Number_of_Tractors__c = input.numberOfTractors;
            carrier.FreightTM__Number_of_Trailers__c = input.numberOfTrailers;
            carrier.FreightTM__Online_GPS_Tracking__c = input.onlineGpsTracking == true;

            carrier.FreightTM__Cargo_Insurance_Amount__c = input.cargoInsuranceAmount;
            carrier.FreightTM__Cargo_Insurance_Expiration__c = input.cargoInsuranceExpiration;
            carrier.FreightTM__Liability_Insurance_Amount__c = input.liabilityInsuranceAmount;
            carrier.FreightTM__Liability_Insurance_Expiration__c = input.liabilityInsuranceExpiration;

            carrier.FreightTM__Remarks__c = input.remarks;

            carrier.FreightTM__On_boarding_Status__c =
                resolveOnboardingStatus(STATUS_SUBMITTED, STATUS_NEW);
            carrier.Overall_Compliance_Status__c = 'Missing Info';
            carrier.Ready_for_Loads__c = false;
            carrier.Onboarding_Submitted_Date__c = System.now();

            if (input.agreementAccepted == true) {
                carrier.Agreement_Status__c = 'Signed';
                carrier.Agreement_Signed_Date__c = System.now();
                carrier.Agreement_Signed_By__c = input.agreementSignedBy;
            } else {
                carrier.Agreement_Status__c = 'Pending';
            }
            carrier.Public_Onboarding_Access__c = true;

            String savedOnboardingStatus =
                upsertCarrierWithStatusFallback(
                    carrier,
                    originalOnboardingStatus
                );

            result.success = true;
            result.carrierId = carrier.Id;
            result.message = 'Carrier information saved.';
            if (savedOnboardingStatus != STATUS_SUBMITTED) {
                result.message +=
                    ' On-boarding Status was saved as ' +
                    (String.isBlank(savedOnboardingStatus)
                        ? 'the existing value'
                        : savedOnboardingStatus) +
                    ' because Submitted is not available for the active Carrier record type.';
            }
            return result;

        } catch (DmlException e) {
            result.success = false;
            result.message = 'Save failed: ' + e.getDmlMessage(0);
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = 'Save failed: ' + e.getTypeName() + ' - ' + e.getMessage();
            return result;
        }
    }

    @AuraEnabled
public static OnboardingResult uploadCarrierDocument(DocumentInput input) {
    OnboardingResult result = new OnboardingResult();

    try {
        if (input.carrierId == null) {
            throw new OnboardingValidationException(
                'Carrier record is required before uploading documents.'
            );
        }

        if (String.isBlank(input.documentType)) {
            throw new OnboardingValidationException(
                'Document Type is required.'
            );
        }

        if (String.isBlank(input.fileName)) {
            throw new OnboardingValidationException(
                'File name is required.'
            );
        }

        if (String.isBlank(input.base64Data)) {
            throw new OnboardingValidationException(
                'File data is required.'
            );
        }

        Carrier_Onboarding_Action__e evt =
            new Carrier_Onboarding_Action__e();

        evt.Carrier_Id__c = String.valueOf(input.carrierId);
        evt.Document_Type__c = input.documentType;
        evt.File_Name__c = input.fileName;
        evt.Base64_Data__c = input.base64Data;
        evt.Event_Time__c = System.now();

        if (input.documentType == 'Signature') {
            evt.Action_Name__c = 'SIGNATURE_SAVED';
        } else {
            evt.Action_Name__c = 'DOCUMENT_UPLOADED';
        }

        Database.SaveResult publishResult =
            EventBus.publish(evt);

        if (!publishResult.isSuccess()) {
            Database.Error err = publishResult.getErrors()[0];

            result.success = false;
            result.carrierId = input.carrierId;
            result.message =
                'Upload failed: ' +
                err.getStatusCode() +
                ' - ' +
                err.getMessage();

            return result;
        }

        result.success = true;
        result.carrierId = input.carrierId;
        result.message =
            input.documentType +
            ' upload received. The file will be attached to the Carrier shortly.';

        return result;

    } catch (Exception e) {
        result.success = false;
        result.message =
            'Upload failed: ' +
            e.getTypeName() +
            ' - ' +
            e.getMessage();

        return result;
    }
}

    @AuraEnabled
    public static OnboardingResult submitForReview(Id carrierId) {
        OnboardingResult result = new OnboardingResult();

        try {
            if (carrierId == null) {
                throw new OnboardingValidationException('Carrier Id is required.');
            }

            FreightTM__Carrier__c carrier = [
                SELECT Id,
                Agreement_Status__c,
                Broker_Carrier_Agreement_Status__c,
                Signature_File_Uploaded__c,
                W9_Status__c,
                MC_Authority_Status__c,
                Insurance_COI_Status__c,
                W_9_File_Uploaded__c,
                MC_Authority_File_Uploaded__c,
                Certificate_of_Insurance_File_Uploaded__c,
                Agreement_File_Uploaded__c
                FROM FreightTM__Carrier__c
                WHERE Id = :carrierId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            Boolean agreementReady =
                carrier.Agreement_Status__c == 'Signed' ||
                carrier.Signature_File_Uploaded__c == true ||
                carrier.Broker_Carrier_Agreement_Status__c == 'Uploaded' ||
                carrier.Broker_Carrier_Agreement_Status__c == 'Approved' ||
                carrier.Agreement_File_Uploaded__c == true;

            Boolean w9Ready =
                carrier.W9_Status__c == 'Uploaded' ||
                carrier.W9_Status__c == 'Approved' ||
                carrier.W_9_File_Uploaded__c == true;

            Boolean mcReady =
                carrier.MC_Authority_Status__c == 'Uploaded' ||
                carrier.MC_Authority_Status__c == 'Approved' ||
                carrier.MC_Authority_File_Uploaded__c == true;

            Boolean insuranceReady =
                carrier.Insurance_COI_Status__c == 'Uploaded' ||
                carrier.Insurance_COI_Status__c == 'Approved' ||
                carrier.Certificate_of_Insurance_File_Uploaded__c == true;

            if (!agreementReady) {
                result.success = false;
                result.carrierId = carrier.Id;
                result.message =
                    'Agreement must be signed or uploaded before submitting for review.';
                return result;
            }

            if (!(w9Ready && mcReady && insuranceReady)) {
                result.success = false;
                result.carrierId = carrier.Id;
                result.message =
                    'Required documents are missing. Please upload W-9, MC Authority, and Certificate of Insurance.';
                return result;
            }

            Carrier_Onboarding_Action__e evt =
                new Carrier_Onboarding_Action__e();

            evt.Carrier_Id__c = String.valueOf(carrier.Id);
            evt.Action_Name__c = 'SUBMIT_FOR_REVIEW';
            evt.Event_Time__c = System.now();

            Database.SaveResult publishResult =
                EventBus.publish(evt);

            if (!publishResult.isSuccess()) {
                Database.Error err = publishResult.getErrors()[0];

                result.success = false;
                result.carrierId = carrier.Id;
                result.message =
                    'Submit failed: ' +
                    err.getStatusCode() +
                    ' - ' +
                    err.getMessage();

                return result;
            }

            result.success = true;
            result.carrierId = carrier.Id;
            result.message = 'Onboarding submitted for compliance review.';
            return result;

        } catch (Exception e) {
            result.success = false;
            result.message =
                'Submit failed: ' +
                e.getTypeName() +
                ' - ' +
                e.getMessage();

            return result;
        }
    }

    private static void validateCarrierInput(CarrierInput input) {
        if (input == null) {
            throw new OnboardingValidationException('Carrier data is required.');
        }

        if (String.isBlank(input.carrierName)) {
            throw new OnboardingValidationException('Carrier Name is required.');
        }

        if (String.isBlank(input.email)) {
            throw new OnboardingValidationException('Email is required.');
        }

        if (String.isBlank(input.phone)) {
            throw new OnboardingValidationException('Phone is required.');
        }

        if (String.isBlank(input.mcNumber) && String.isBlank(input.usdotNumber)) {
            throw new OnboardingValidationException('MC/MX/FF Number or USDOT Number is required.');
        }

        if (!String.isBlank(input.scacCode) && input.scacCode.length() > 5) {
            throw new OnboardingValidationException('SCAC Code must be 5 characters or less.');
        }

        if (!String.isBlank(input.mcNumber) && input.mcNumber.length() > 10) {
            throw new OnboardingValidationException('MC/MX/FF Number must be 10 characters or less.');
        }

        if (!String.isBlank(input.usdotNumber) && input.usdotNumber.length() > 10) {
            throw new OnboardingValidationException('USDOT Number must be 10 characters or less.');
        }

        if (!String.isBlank(input.federalId) && input.federalId.length() > 10) {
            throw new OnboardingValidationException('Federal ID must be 10 characters or less.');
        }

        if (!String.isBlank(input.zipCode) && input.zipCode.length() > 10) {
            throw new OnboardingValidationException('Zip Code must be 10 characters or less.');
        }

        if (!String.isBlank(input.billingZipCode) && input.billingZipCode.length() > 10) {
            throw new OnboardingValidationException('Billing Zip Code must be 10 characters or less.');
        }

        if (String.isBlank(input.primaryContact)) {
            throw new OnboardingValidationException(
                'Primary Contact is required.'
            );
        }

        if (String.isBlank(input.preferredLanes)) {
            throw new OnboardingValidationException(
                'Preferred Lanes is required.'
            );
        }

        if (input.numberOfDrivers == null) {
            throw new OnboardingValidationException(
                'Number of Drivers is required.'
            );
        }

        if (input.numberOfDrivers < 0) {
            throw new OnboardingValidationException(
                'Number of Drivers cannot be negative.'
            );
        }

        if (input.numberOfTractors == null) {
            throw new OnboardingValidationException(
                'Number of Tractors is required.'
            );
        }

        if (input.numberOfTractors < 0) {
            throw new OnboardingValidationException(
                'Number of Tractors cannot be negative.'
            );
        }

        if (input.numberOfTrailers == null) {
            throw new OnboardingValidationException(
                'Number of Trailers is required.'
            );
        }

        if (input.numberOfTrailers < 0) {
            throw new OnboardingValidationException(
                'Number of Trailers cannot be negative.'
            );
        }

        if (input.cargoInsuranceAmount == null) {
            throw new OnboardingValidationException(
                'Cargo Insurance Amount is required.'
            );
        }

        if (input.cargoInsuranceAmount <= 0) {
            throw new OnboardingValidationException(
                'Cargo Insurance Amount must be greater than zero.'
            );
        }

        if (input.cargoInsuranceExpiration == null) {
            throw new OnboardingValidationException(
                'Cargo Insurance Expiration is required.'
            );
        }

        if (input.liabilityInsuranceAmount == null) {
            throw new OnboardingValidationException(
                'Liability Insurance Amount is required.'
            );
        }

        if (input.liabilityInsuranceAmount <= 0) {
            throw new OnboardingValidationException(
                'Liability Insurance Amount must be greater than zero.'
            );
        }

        if (
            input.liabilityInsuranceExpiration ==
            null
        ) {
            throw new OnboardingValidationException(
                'Liability Insurance Expiration is required.'
            );
        }

        if (input.agreementAccepted != true) {
            throw new OnboardingValidationException(
                'You must accept the broker-carrier agreement before continuing.'
            );
        }

        if (
            String.isBlank(
                input.agreementSignedBy
            )
        ) {
            throw new OnboardingValidationException(
                'Signed By is required before continuing.'
            );
        }

        Set<String> validModes = new Set<String>{
            'LTL',
                'Air Freight',
                'Cargo Van',
                'Semi'
                };

                    if (!String.isBlank(input.mode)) {
                        for (String modeValue : input.mode.split(';')) {
                            if (!validModes.contains(modeValue)) {
                                throw new OnboardingValidationException('Invalid Mode value: ' + modeValue);
                            }
                        }
                    }

        if (input.agreementAccepted == true && String.isBlank(input.agreementSignedBy)) {
            throw new OnboardingValidationException('Signer name is required when accepting the agreement.');
        }
    }

    private static void updateCarrierDocumentSummary(
        Id carrierId,
        String documentType,
        Id contentDocumentId
    ) {
        FreightTM__Carrier__c carrier = new FreightTM__Carrier__c(Id = carrierId);

        if (documentType == 'W-9') {
            carrier.W_9_File_Uploaded__c = true;
            carrier.W9_Status__c = 'Uploaded';

        } else if (documentType == 'MC Authority') {
            carrier.MC_Authority_File_Uploaded__c = true;
            carrier.MC_Authority_Status__c = 'Uploaded';

        } else if (documentType == 'Certificate of Insurance') {
            carrier.Certificate_of_Insurance_File_Uploaded__c = true;
            carrier.Insurance_COI_Status__c = 'Uploaded';

        } else if (documentType == 'Broker Carrier Agreement') {
            carrier.Agreement_File_Uploaded__c = true;
            carrier.Broker_Carrier_Agreement_Status__c = 'Uploaded';

        } else if (documentType == 'Signature') {
            carrier.Signature_File_Uploaded__c = true;
            carrier.Agreement_Status__c = 'Signed';
            carrier.Agreement_Signed_Date__c = System.now();
        }

        carrier.FreightTM__On_boarding_Status__c =
            resolveOnboardingStatus(STATUS_DOCUMENTS_PENDING, STATUS_NOT_COMPLETE);
        carrier.Overall_Compliance_Status__c = 'Missing Info';
        carrier.Ready_for_Loads__c = false;

        update as system carrier;
    }

    private static String buildDocumentFileName(String originalFileName, String documentType) {
        if (String.isBlank(originalFileName)) {
            originalFileName = 'Carrier Document';
        }

        String extension = '';
        String baseName = originalFileName;

        Integer dotIndex = originalFileName.lastIndexOf('.');
        if (dotIndex > 0) {
            baseName = originalFileName.substring(0, dotIndex);
            extension = originalFileName.substring(dotIndex);
        }

        return baseName + ' - ' + documentType + extension;
    }

    private static String removeFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Uploaded File';
        }

        Integer dotIndex = fileName.lastIndexOf('.');
        if (dotIndex > 0) {
            return fileName.substring(0, dotIndex);
        }

        return fileName;
    }

    /**
     * Returns an active API value from the managed On-boarding Status picklist.
     * The preferred value is used first, followed by the fallback and then the
     * first active value available in the target org.
     */
    public static String resolveOnboardingStatus(
        String preferredStatus,
        String fallbackStatus
    ) {
        List<Schema.PicklistEntry> entries =
            FreightTM__Carrier__c.FreightTM__On_boarding_Status__c
                .getDescribe()
                .getPicklistValues();

        Set<String> activeValues = new Set<String>();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                activeValues.add(entry.getValue());
            }
        }

        if (
            !String.isBlank(preferredStatus) &&
            activeValues.contains(preferredStatus)
        ) {
            return preferredStatus;
        }

        if (
            !String.isBlank(fallbackStatus) &&
            activeValues.contains(fallbackStatus)
        ) {
            return fallbackStatus;
        }

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    /**
     * Saves the Carrier with Submitted when the value is available to the
     * active record type. If Salesforce rejects that restricted picklist
     * value, the method retries with New and finally preserves the previous
     * value so the public onboarding submission is not lost.
     */
    private static String upsertCarrierWithStatusFallback(
        FreightTM__Carrier__c carrier,
        String originalOnboardingStatus
    ) {
        try {
            upsert as system carrier;
            return carrier.FreightTM__On_boarding_Status__c;
        } catch (DmlException firstError) {
            if (!isOnboardingStatusPicklistError(firstError)) {
                throw firstError;
            }

            String fallbackStatus =
                resolveOnboardingStatus(STATUS_NEW, originalOnboardingStatus);

            if (
                !String.isBlank(fallbackStatus) &&
                fallbackStatus != carrier.FreightTM__On_boarding_Status__c
            ) {
                carrier.FreightTM__On_boarding_Status__c = fallbackStatus;
                try {
                    upsert as system carrier;
                    return fallbackStatus;
                } catch (DmlException fallbackError) {
                    if (!isOnboardingStatusPicklistError(fallbackError)) {
                        throw fallbackError;
                    }
                }
            }

            carrier.FreightTM__On_boarding_Status__c =
                originalOnboardingStatus;
            upsert as system carrier;
            return originalOnboardingStatus;
        }
    }

    private static Boolean isOnboardingStatusPicklistError(
        DmlException error
    ) {
        if (error == null) {
            return false;
        }

        String message = error.getMessage();
        if (String.isBlank(message)) {
            return false;
        }

        String normalized = message.toLowerCase();
        return
            normalized.contains('restricted picklist') &&
            (
                normalized.contains('on-boarding status') ||
                normalized.contains('on_boarding_status')
            );
    }

}