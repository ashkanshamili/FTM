public without sharing class HighwayLoadService {
    @TestVisible
    private static String brokerEmailOverride;
    
    @TestVisible
    private static Blob rateConPdfOverride;
    
    @TestVisible
    private static Boolean testForceManualSendError = false;
    
    @TestVisible
    private static String testManualSendResponse;
    
    @TestVisible
    private static Blob totalRateConPdfOverride;
    
    public class HighwayManualSendException extends Exception {}
    
    // ===============================
    // ENTRY FROM TRIGGER (ASYNC)
    // ===============================
    @future(callout=true)
    public static void processLoadsAsync(Set<Id> loadIds) {
        if (loadIds == null || loadIds.isEmpty()) {
            return;
        }
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            FreightTM__Carrier_Obj__c
            FROM FreightTM__Load__c
            WHERE Id IN :loadIds
        ];
        
        Set<Id> carrierIds = new Set<Id>();
        for (FreightTM__Load__c load : loads) {
            if (load.FreightTM__Carrier_Obj__c != null) {
                carrierIds.add(load.FreightTM__Carrier_Obj__c);
            }
        }
        
        Map<Id, FreightTM__Carrier__c> carrierMap =
            new Map<Id, FreightTM__Carrier__c>([
                SELECT Id,
                FreightTM__USDOT_Number__c,
                FreightTM__MC_MX_FF_Number__c
                FROM FreightTM__Carrier__c
                WHERE Id IN :carrierIds
            ]);
        
        List<FreightTM__Load__c> loadsToUpdate = new List<FreightTM__Load__c>();
        
        for (FreightTM__Load__c load : loads) {
            FreightTM__Carrier__c carrier = carrierMap.get(load.FreightTM__Carrier_Obj__c);
            if (carrier == null) {
                continue;
            }
            
            String dotNumber = carrier.FreightTM__USDOT_Number__c;
            String mcNumber  = carrier.FreightTM__MC_MX_FF_Number__c;
            
            if (String.isBlank(dotNumber) && String.isBlank(mcNumber)) {
                continue;
            }
            
            checkCarrier(dotNumber, mcNumber, load.Id, loadsToUpdate);
        }
        
        if (!loadsToUpdate.isEmpty()) {
            Map<Id, FreightTM__Load__c> mergedUpdates = new Map<Id, FreightTM__Load__c>();
            
            for (FreightTM__Load__c row : loadsToUpdate) {
                if (row == null || row.Id == null) {
                    continue;
                }
                
                if (!mergedUpdates.containsKey(row.Id)) {
                    mergedUpdates.put(row.Id, row);
                } else {
                    FreightTM__Load__c existing = mergedUpdates.get(row.Id);
                    Map<String, Object> populatedFields = row.getPopulatedFieldsAsMap();
                    
                    for (String fieldName : populatedFields.keySet()) {
                        if (fieldName != 'Id') {
                            existing.put(fieldName, populatedFields.get(fieldName));
                        }
                    }
                }
            }
            
            update mergedUpdates.values();
        }
    }
    
    // ===============================
    // STEP 2 — CHECK CARRIER
    // ===============================
    public static void checkCarrier(
        String dotNumber,
        String mcNumber,
        Id loadId,
        List<FreightTM__Load__c> loadsToUpdate
    ) {
        HttpResponse res = null;
        // Sandbox
        //if (String.isNotBlank(dotNumber)) {
        //    res = HighwayAPIService.makeApiCall(
        //        'https://staging.highway.com/core/connect/external_api/v1/carriers/' + dotNumber + '/by_dot_number',
        //        'GET'
        //    );
        //}
        //Production
        if (String.isNotBlank(dotNumber)) {
            res = HighwayAPIService.makeApiCall(
                HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/carriers/' + dotNumber + '/by_dot_number',
                'GET'
            );
        }
        //Sandbox
        //if ((res == null || res.getStatusCode() == 404) && String.isNotBlank(mcNumber)) {
        //    res = HighwayAPIService.makeApiCall(
        //        'https://staging.highway.com/core/connect/external_api/v1/carriers/mc_number/' + mcNumber + '/by_identifier',
        //        'GET'
        //    );
        //}
        //Production
        if ((res == null || res.getStatusCode() == 404) && String.isNotBlank(mcNumber)) {
            res = HighwayAPIService.makeApiCall(
                HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/carriers/mc_number/' + mcNumber + '/by_identifier',
                'GET'
            );
        }
        
        if (res == null || res.getStatusCode() == 404) {
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_Status__c = 'Not Found',
                Highway_Rules_Result__c = 'fail',
                Highway_Connection_Status__c = 'unknown'
            ));
            return;
        }
        
        if (res.getStatusCode() != 200) {
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_Status__c = 'Error'
            ));
            system.debug('Highway_Status__Error' + res.getStatusCode());
            system.debug('Highway_Status__Error_message' + res.getBody());
            return;
        }
        
        Map<String, Object> result =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object parsedResponse = JSON.deserializeUntyped(res.getBody());
        System.debug('Highway Carrier Full Response Body JSON:\n' + JSON.serializePretty(parsedResponse));

        
        String highwayCarrierId = String.valueOf(result.get('id'));
        String carrierContactEmails = extractCarrierContactEmails(result);
        
        System.debug('Highway Carrier Full Response Body: ' + res.getBody());
        System.debug('Highway Carrier Extracted Contact Emails: ' + carrierContactEmails);
        System.debug('Highway Carrier Extracted Contact Emails is blank? ' + String.isBlank(carrierContactEmails));
        
        String rulesResult = 'unknown';
        Object rulesAssessmentObj = result.get('rules_assessment');
        if (rulesAssessmentObj instanceof Map<String, Object>) {
            Map<String, Object> rulesAssessment = (Map<String, Object>) rulesAssessmentObj;
            if (rulesAssessment.get('overall_result') != null) {
                rulesResult = String.valueOf(rulesAssessment.get('overall_result'));
            }
        }
        
        String connectionStatus = 'unknown';
        Object connectionObj = result.get('connection');
        if (connectionObj instanceof Map<String, Object>) {
            Map<String, Object> connection = (Map<String, Object>) connectionObj;
            if (connection.get('status') != null) {
                connectionStatus = String.valueOf(connection.get('status'));
            }
        }
        
        if (rulesResult == 'fail') {
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_Carrier_ID__c = highwayCarrierId,
                Highway_Status__c = 'Not Approved',
                Highway_Rules_Result__c = rulesResult,
                Highway_Connection_Status__c = connectionStatus,
                Highway_Carrier_Contact_Emails__c = carrierContactEmails
            ));
            return;
        }
        
        upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
            Id = loadId,
            Highway_Carrier_ID__c = highwayCarrierId,
            Highway_Status__c = 'Approved',
            Highway_Rules_Result__c = rulesResult,
            Highway_Connection_Status__c = connectionStatus,
            Highway_Carrier_Contact_Emails__c = carrierContactEmails
        ));
        
        //createRateConfirmation(highwayCarrierId, loadId, loadsToUpdate);
    }
    
    // ===============================
    // STEP 3 — CREATE RATE CONFIRMATION Automatic
    // ===============================
    public static void createRateConfirmation(
        String highwayCarrierId,
        Id loadId,
        List<FreightTM__Load__c> loadsToUpdate
    ) {
        String brokerEmail = getBrokerEmail(loadId);
        Blob pdfBlob = getRateConPdfBlob(loadId);
        
        if (String.isBlank(highwayCarrierId) || pdfBlob == null || pdfBlob.size() == 0 || String.isBlank(brokerEmail)) {
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = 'Error'
            ));
            return;
        }
        
        String boundary = '----HighwayBoundary' + String.valueOf(Datetime.now().getTime());
        String externalId = String.valueOf(loadId) + '-' + String.valueOf(Datetime.now().getTime());
        
        MultipartFormBuilder form = new MultipartFormBuilder(boundary);
        form.addField('rate_confirmation[carrier_id]', highwayCarrierId);
        form.addField('rate_confirmation[external_id]', externalId);
        form.addField('rate_confirmation[external_load_id]', String.valueOf(loadId));
        form.addField('rate_confirmation[broker_load_owner_email]', brokerEmail);
        form.addFile('rate_confirmation[attachments][]', 'rate_confirmation.pdf', 'application/pdf', pdfBlob);
        
        HttpRequest req = new HttpRequest();
        //req.setEndpoint('https://staging.highway.com/core/connect/external_api/v1/rate_confirmations');//Sandbox
        req.setEndpoint(HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/rate_confirmations');
        req.setMethod('POST');
        
        String authHeader = HighwayAPIService.HIGHWAY_API_KEY;
        if (!String.isBlank(authHeader) && !authHeader.startsWith('Bearer ')) {
            authHeader = 'Bearer ' + authHeader;
        }
        
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', 'application/json');
        req.setBodyAsBlob(form.build());
        req.setTimeout(60000);
        
        HttpResponse res = new Http().send(req);
        
        System.debug('RC Response Code: ' + res.getStatusCode());
        System.debug('RC Response Body: ' + res.getBody());
        System.debug('RC Carrier Id: ' + highwayCarrierId);
        System.debug('RC External Id: ' + externalId);
        System.debug('RC External Load Id: ' + String.valueOf(loadId));
        System.debug('RC Broker Email: ' + brokerEmail);
        System.debug('RC PDF Size: ' + pdfBlob.size());
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            String rcStatus = 'created';
            
            if (String.isNotBlank(res.getBody())) {
                try {
                    Map<String, Object> result =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    
                    if (result.containsKey('status') && result.get('status') != null) {
                        Map<String, String> statuses = new Map<String, String>{
                            'pending' => 'Pending'
                                };
                                    
                                    String apiStatus = String.valueOf(result.get('status'));
                        rcStatus = statuses.containsKey(apiStatus) ? statuses.get(apiStatus) : apiStatus;
                    }
                } catch (Exception ex) {
                    System.debug('Unable to parse RC response body: ' + ex.getMessage());
                }
            }
            
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = rcStatus
            ));
        } else {
            upsertLoadUpdate(loadsToUpdate, new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = 'Error'
            ));
        }
    }
    
    // ===============================
    // STEP 3 — CREATE and Send RATE CONFIRMATION Manual
    // ===============================
    @AuraEnabled
    public static String sendRateConfirmationManually(Id loadId) {
        return sendRateConfirmationManually(loadId, null);
    }
    
    public static String sendRateConfirmationManually(Id loadId, String selectedTargetEmail) {
        //FreightTM__Load__c load = [
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            Highway_Carrier_ID__c,
            Highway_Carrier_Contact_Emails__c,
            Highway_Status__c,
            Highway_Rules_Result__c,
            Highway_Connection_Status__c,
            Highway_RC_Status__c,
            Highway_RC_ID__c,
            Highway_Target_Email__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        
        if (loads.isEmpty()) {
            throw new HighwayManualSendException('Load not found.');
        }
        FreightTM__Load__c load = loads[0];
        
        if (String.isBlank(load.Highway_Carrier_ID__c)) {
            throw new HighwayManualSendException('Highway Carrier ID is missing.');
        }
        
        if (load.Highway_Status__c != 'Approved') {
            throw new HighwayManualSendException('Carrier is not Highway approved.');
        }
        
        // Ensure the Load can be used for PDF generation
        getOrCreateCarrierRate(load.Id);
        
        Boolean resend = String.isNotBlank(load.Highway_RC_ID__c);
        List<String> targetedEmails = new List<String>();
        
        if (String.isNotBlank(selectedTargetEmail)) {
            targetedEmails.add(selectedTargetEmail.trim());
        }
        
        System.debug('Manual selectedTargetEmail from VF: ' + selectedTargetEmail);
        System.debug('Manual targetedEmails sent to Highway: ' + targetedEmails);
        
        sendRateConfirmation(
            load.Id,
            load.Highway_Carrier_ID__c,
            targetedEmails,
            resend
        );
        return resend ? 'Rate confirmation resent successfully.' : 'Rate confirmation sent successfully.';
    }
    
    public static String sendRateConfirmationFromVF(Id loadId) {
        return sendRateConfirmationFromVF(loadId, null);
    }
    
    public static String sendRateConfirmationFromVF(Id loadId, String selectedTargetEmail) {
        if (Test.isRunningTest()) {
            if (testForceManualSendError) {
                throw new HighwayManualSendException('Forced test error');
            }
            if (testManualSendResponse != null) {
                return testManualSendResponse;
            }
        }
        
        System.debug('VF selectedTargetEmail: ' + selectedTargetEmail);
        
        return sendRateConfirmationManually(loadId, selectedTargetEmail);
    }
    
    // SEND TO HIGHWAY
    public static void sendRateConfirmation(
        Id loadId,
        String highwayCarrierId,
        List<String> targetedEmails,
        Boolean resend
    ) {
        String brokerEmail = getBrokerEmail(loadId);
        Blob pdfBlob = getRateConPdfBlob(loadId);
        
        if (String.isBlank(highwayCarrierId)) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = 'Error'
            );
            throw new HighwayManualSendException('Highway Carrier ID is missing.');
        }

        if (String.isBlank(brokerEmail)) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = 'Error'
            );
            throw new HighwayManualSendException('Broker email is missing.');
        }

        if (pdfBlob == null || pdfBlob.size() == 0) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_RC_Status__c = 'Error'
            );
            throw new HighwayManualSendException(
                'The Load could not be used to generate the Rate Confirmation PDF.'
            );
        }
        
        
        String boundary = '----HighwayBoundary' + String.valueOf(Datetime.now().getTime());
        String externalId = String.valueOf(loadId) + '-' + String.valueOf(Datetime.now().getTime());
        
        MultipartFormBuilder form = new MultipartFormBuilder(boundary);
        form.addField('rate_confirmation[carrier_id]', highwayCarrierId);
        form.addField('rate_confirmation[external_id]', externalId);
        form.addField('rate_confirmation[external_load_id]', String.valueOf(loadId));
        form.addField('rate_confirmation[broker_load_owner_email]', brokerEmail);
        
        if (targetedEmails != null && !targetedEmails.isEmpty()) {
            for (String email : targetedEmails) {
                if (String.isNotBlank(email)) {
                    form.addField('rate_confirmation[targeted_emails][]', email.trim());
                }
            }
        }
        
        form.addFile(
            'rate_confirmation[attachments][]',
            'rate_confirmation.pdf',
            'application/pdf',
            pdfBlob
        );
        
        HttpRequest req = new HttpRequest();
        // Sandbox
         //req.setEndpoint('https://staging.highway.com/core/connect/external_api/v1/rate_confirmations');
        // Production
        req.setEndpoint(HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/rate_confirmations');
        req.setMethod('POST');
        
        String authHeader = HighwayAPIService.HIGHWAY_API_KEY;
        if (!String.isBlank(authHeader) && !authHeader.startsWith('Bearer ')) {
            authHeader = 'Bearer ' + authHeader;
        }
        
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', 'application/json');
        req.setBodyAsBlob(form.build());
        req.setTimeout(60000);
        
        HttpResponse res = new Http().send(req);
        
        System.debug('Manual RC Response Code: ' + res.getStatusCode());
        System.debug('Manual RC Response Body: ' + res.getBody());
        System.debug('Manual targetedEmails: ' + targetedEmails);
        System.debug('Manual broker email: ' + brokerEmail);
        
        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(Id = loadId);
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            String rcStatus = 'Pending';
            
            if (String.isNotBlank(res.getBody())) {
                try {
                    Map<String, Object> result =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    
                    if (result.containsKey('status') && result.get('status') != null) {
                        Map<String, String> statuses = new Map<String, String>{
                            'pending'   => 'Pending',
                                'sent'      => 'Sent',
                                'viewed'    => 'Viewed',
                                'signed'    => 'Signed',
                                'delivered' => 'Delivered',
                                'rejected'  => 'Rejected',
                                'voided'    => 'Voided',
                                'accepted'  => 'Accepted'
                                };
                                    
                                    String apiStatus = String.valueOf(result.get('status')).toLowerCase();
                        rcStatus = statuses.containsKey(apiStatus) ? statuses.get(apiStatus) : apiStatus;
                    }
                    
                    if (result.containsKey('id') && result.get('id') != null) {
                        loadUpdate.Highway_RC_ID__c = String.valueOf(result.get('id'));
                    }
                    
                } catch (Exception ex) {
                    System.debug('Unable to parse RC response body: ' + ex.getMessage());
                }
            }
            
            loadUpdate.Highway_RC_Status__c = rcStatus;
        } else {
            loadUpdate.Highway_RC_Status__c = 'Error';
            update loadUpdate;
            throw new HighwayManualSendException(
                'Highway returned an error. Status code: ' + res.getStatusCode() + '. Body: ' + res.getBody()
            );
        }
        
        update loadUpdate;
    }
    
    @future(callout=true)
    public static void sendTotalRateConfirmationAfterFirstAcceptedAsync(Id loadId) {
        System.debug('TOTAL RC FUTURE WRAPPER STARTED. Load Id: ' + loadId);
        sendTotalRateConfirmationNow(loadId);
    }
    
    
    // ===============================
    // ENSURE CARRIER RATE EXISTS
    // ===============================
    private static Id getOrCreateCarrierRate(Id loadId) {
        // The FTM RateCon pages in this project use FreightTM__Load__c as the standard controller.
        // Therefore the Load Id is the PDF record Id; no extra rate object is required.
        return loadId;
    }

    // ===============================
    // HELPERS
    // ===============================
    
    // ====================================================
    // Sends a custom notification or email to the dispatcher
    // when a carrier is blocked by Highway.
    // ====================================================
    public static void notifyDispatcher(Id loadId, String reason) {
        try {
            // Query load owner for email
            //FreightTM__Load__c load = [
            List<FreightTM__Load__c> loads = [
                SELECT FreightTM__Dispatch__c,
           		FreightTM__Dispatch__r.Email, Name
                FROM FreightTM__Load__c
                WHERE Id = :loadId
                LIMIT 1
            ];
            
            if (loads.isEmpty()) {
                return;
            }

            FreightTM__Load__c load = loads[0];
            if (load.FreightTM__Dispatch__r == null || String.isBlank(load.FreightTM__Dispatch__r.Email)) {
                return;
            }
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ load.FreightTM__Dispatch__r.Email });
            mail.setSubject('Highway: Carrier Not Approved — Load ' + load.Name);
            mail.setPlainTextBody(
                'The carrier on Load ' + load.Name + ' could not be approved by Highway.\n\n'
                + 'Reason: ' + reason + '\n\n'
                + 'Please review the carrier or assign a different carrier before proceeding.'
            );
            //Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            
        } catch (Exception e) {
            System.debug('notifyDispatcher error: ' + e.getMessage());
        }
    }
    
    // =================================================
    // Gets the broker email for the rate confirmation.
    // Tries load owner first, falls back to a custom setting.
    // =================================================
    private static String getBrokerEmail(Id loadId) {
        if (Test.isRunningTest() && brokerEmailOverride != null) {
            return brokerEmailOverride;
        }
        
        try {
            //FreightTM__Load__c load = [
            List<FreightTM__Load__c> loads = [
                SELECT FreightTM__Dispatch__c,
           		FreightTM__Dispatch__r.Email
                FROM FreightTM__Load__c
                WHERE Id = :loadId
                LIMIT 1
            ];
            if (!loads.isEmpty() &&
                loads[0].FreightTM__Dispatch__r != null &&
                String.isNotBlank(loads[0].FreightTM__Dispatch__r.Email)) {
                System.debug('Dispatcher Email: ' + loads[0].FreightTM__Dispatch__r.Email);
                return loads[0].FreightTM__Dispatch__r.Email;
                
                //String.isNotBlank(load.FreightTM__Dispatch__r.Email)) {
                //return load.FreightTM__Dispatch__r.Email;
            }
        } catch (Exception e) {
            System.debug('getBrokerEmail error: ' + e.getMessage());
        }
        
        return 'yourcompany@email.com';
    }
    
    private static void upsertLoadUpdate(List<FreightTM__Load__c> loadsToUpdate, FreightTM__Load__c newRow) {
        if (newRow == null || newRow.Id == null) {
            return;
        }
        
        for (FreightTM__Load__c existing : loadsToUpdate) {
            if (existing.Id == newRow.Id) {
                Map<String, Object> populatedFields = newRow.getPopulatedFieldsAsMap();
                for (String fieldName : populatedFields.keySet()) {
                    if (fieldName != 'Id') {
                        existing.put(fieldName, populatedFields.get(fieldName));
                    }
                }
                return;
            }
        }
        
        loadsToUpdate.add(newRow);
    }
    
    private static Id getExistingCarrierRateId(Id loadId) {
        return loadId;
    }

    @TestVisible
    private static String getRateConPdfRawString(Id loadId) {
        if (Test.isRunningTest()) {
        return EncodingUtil.base64Encode(Blob.valueOf('fake pdf body'));
    }
        
        Id carrierRateId = getOrCreateCarrierRate(loadId);
        if (carrierRateId == null) {
            System.debug('Unable to resolve the Load for RateCon PDF generation: ' + loadId);
            return null;
        }
        
        PageReference pdfPage = Page.RateCon; 
        //pdfPage.getParameters().put('id', rates[0].Id);
        pdfPage.getParameters().put('id', carrierRateId);
        
        try {
            Blob pdfBlob = pdfPage.getContentAsPDF();
            return EncodingUtil.base64Encode(pdfBlob); 
        } catch (Exception e) {
            System.debug('PDF generation error: ' + e.getMessage());
            return null;
        }
    }
    
    private static Blob getRateConPdfBlob(Id loadId) {
        if (Test.isRunningTest() && rateConPdfOverride != null) {
            return rateConPdfOverride;
        }
        
        Id carrierRateId = getOrCreateCarrierRate(loadId);
        if (carrierRateId == null) {
            System.debug('Unable to resolve the Load for RateCon PDF generation: ' + loadId);
            return null;
        }
        
        PageReference pdfPage = Page.RateCon;
        //pdfPage.getParameters().put('id', rates[0].Id);
        pdfPage.getParameters().put('id', carrierRateId);
        
        try {
            return pdfPage.getContentAsPDF();
        } catch (Exception e) {
            System.debug('PDF generation error: ' + e.getMessage());
            return null;
        }
    }
       
    private static Blob getTotalRateConPdfBlob(Id loadId) {
        if (Test.isRunningTest() && totalRateConPdfOverride != null) {
            return totalRateConPdfOverride;
        }
        if (loadId == null) {
            System.debug('TOTAL RC STOPPED: Load Id is null.');
            return null;
        }
        
        Id carrierRateId = getOrCreateCarrierRate(loadId);
        //Id carrierRateId = getExistingCarrierRateId(loadId);
        
        if (carrierRateId == null) {
            System.debug('TOTAL RC STOPPED: Load could not be resolved for PDF generation: ' + loadId);
            return null;
        }
        System.debug('TOTAL RC Load Id used for PDF: ' + carrierRateId);
        System.debug('TOTAL RC PDF RUNNING USER ID: ' + UserInfo.getUserId());
        System.debug('TOTAL RC PDF RUNNING USER NAME: ' + UserInfo.getName());
        System.debug('TOTAL RC PDF RUNNING USER TYPE: ' + UserInfo.getUserType());


        PageReference pdfPage = Page.RateConTotal;
        pdfPage.getParameters().put('id', carrierRateId);

        try {
            Blob pdfBlob = pdfPage.getContentAsPDF();
            Integer pdfSize = pdfBlob == null ? 0 : pdfBlob.size();
            
            System.debug('TOTAL RC generated PDF blob is null? ' + (pdfBlob == null));
            System.debug('TOTAL RC generated PDF blob size: ' + pdfSize);

            // A real populated RateCon should not be 789 bytes.
            // This prevents Highway from receiving a blank PDF.
            if (pdfBlob == null || pdfSize < 5000) {
                System.debug('TOTAL RC STOPPED: PDF is too small, likely blank. Size=' + pdfSize);
                return null;
            }
            
            return pdfBlob;
            //return pdfPage.getContentAsPDF();
        } catch (Exception e) {
            System.debug('Total RC PDF generation error: ' + e.getMessage());
            System.debug('Total RC PDF generation stack: ' + e.getStackTraceString());
            return null;
        }
    }
    
    public static void markTotalRateConfirmationReady(Id loadId) {
        if (loadId == null) {
            System.debug('TOTAL RC READY STOPPED: Load Id is null.');
            return;
        }
        
        try {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_TotalRC_Sent__c = false,
                Highway_TotalRC_Status__c = 'Ready to Send'
            );
            
            System.debug('TOTAL RC marked Ready to Send. Load Id: ' + loadId);
            
        } catch (Exception e) {
            System.debug('markTotalRateConfirmationReady error: ' + e.getMessage());
            System.debug('markTotalRateConfirmationReady stack: ' + e.getStackTraceString());
        }
    }
    
    @AuraEnabled
    public static String sendTotalRateConfirmationManually(Id loadId) {
        //sendTotalRateConfirmationNow(loadId);
        //return 'Total Rate Confirmation sent successfully.';
        return sendTotalRateConfirmationManually(loadId, null);
        
    }
    
    public static String sendTotalRateConfirmationManually(
        Id loadId,
        String selectedTargetEmail
    ) {
        sendTotalRateConfirmationNow(loadId, selectedTargetEmail);
        return 'Total Rate Confirmation sent successfully.';
    }
    
    public static String sendTotalRateConfirmationFromVF(Id loadId) {
        return sendTotalRateConfirmationFromVF(loadId, null);
    }
    
    public static String sendTotalRateConfirmationFromVF(
        Id loadId,
        String selectedTargetEmail
    ) {
        if (Test.isRunningTest()) {
            if (testForceManualSendError) {
                throw new HighwayManualSendException('Forced test error');
            }
            if (testManualSendResponse != null) {
                return testManualSendResponse;
            }
        }
        
        System.debug('Total RC VF selectedTargetEmail: ' + selectedTargetEmail);
        
        return sendTotalRateConfirmationManually(loadId, selectedTargetEmail);
    }
    
    public static void sendTotalRateConfirmationNow(
        Id loadId,
        String selectedTargetEmail
    ) {
        System.debug('TOTAL RC SEND STARTED. Load Id: ' + loadId);
        System.debug('TOTAL RC RUNNING USER ID: ' + UserInfo.getUserId());
        System.debug('TOTAL RC RUNNING USER NAME: ' + UserInfo.getName());
        System.debug('TOTAL RC RUNNING USER TYPE: ' + UserInfo.getUserType());
        System.debug('TOTAL RC RUNNING PROFILE ID: ' + UserInfo.getProfileId());
        
        if (loadId == null) {
            System.debug('TOTAL RC STOPPED: Load Id is null.');
            throw new HighwayManualSendException('Load Id is missing.');
        }
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            Highway_Carrier_ID__c,
            Highway_Target_Email__c,
            Highway_TotalRC_ID__c,
            Highway_TotalRC_Sent__c,
            Highway_TotalRC_Status__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        
        if (loads.isEmpty()) {
            System.debug('TOTAL RC STOPPED: Load not found.');
            throw new HighwayManualSendException('Load not found.');
        }
        
        FreightTM__Load__c load = loads[0];
        
        System.debug('TOTAL RC LOAD DATA: CarrierId=' + load.Highway_Carrier_ID__c);
        System.debug('TOTAL RC LOAD DATA: TargetEmail=' + load.Highway_Target_Email__c);
        System.debug('TOTAL RC LOAD DATA: SelectedTargetEmail=' + selectedTargetEmail);
        System.debug('TOTAL RC LOAD DATA: TotalRCId=' + load.Highway_TotalRC_ID__c);
        System.debug('TOTAL RC LOAD DATA: TotalRCSent=' + load.Highway_TotalRC_Sent__c);
        System.debug('TOTAL RC LOAD DATA: TotalRCStatus=' + load.Highway_TotalRC_Status__c);
        

        if (hasActiveTotalRc(load)) {
            System.debug(
                'TOTAL RC STOPPED: Active Total RC already exists. ' +
                'TotalRCId=' + load.Highway_TotalRC_ID__c +
                ', Status=' + load.Highway_TotalRC_Status__c
            );
            
            throw new HighwayManualSendException(
                'Total Rate Confirmation is still active. Cancel it before sending a new one.'
            );
        }
        
        if (String.isBlank(load.Highway_Carrier_ID__c)) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_TotalRC_Sent__c = false,
                Highway_TotalRC_Status__c = 'Error'
            );
            
            System.debug('TOTAL RC STOPPED: Highway Carrier ID is blank.');
            throw new HighwayManualSendException('Highway Carrier ID is missing.');
        }
        
        String targetEmailToSend = String.isNotBlank(selectedTargetEmail)
            ? selectedTargetEmail.trim()
            : load.Highway_Target_Email__c;
        
        if (String.isBlank(targetEmailToSend)) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_TotalRC_Sent__c = false,
                Highway_TotalRC_Status__c = 'Error'
            );
            
            System.debug('TOTAL RC STOPPED: Target email is blank.');
            throw new HighwayManualSendException(
                'Target email is required for Total Rate Confirmation.'
            );
        }
        
        String brokerEmail = getBrokerEmail(loadId);
        System.debug('TOTAL RC Broker Email: ' + brokerEmail);
        
        if (String.isBlank(brokerEmail)) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_TotalRC_Sent__c = false,
                Highway_TotalRC_Status__c = 'Error'
            );
            
            System.debug('TOTAL RC STOPPED: Broker email is blank.');
            throw new HighwayManualSendException('Broker email is missing.');
        }
        
        Blob pdfBlob = getTotalRateConPdfBlob(loadId);
        
        if (pdfBlob == null || pdfBlob.size() < 5000) {
            update new FreightTM__Load__c(
                Id = loadId,
                Highway_TotalRC_Sent__c = false,
                Highway_TotalRC_Status__c = 'Error'
            );
            
            System.debug('TOTAL RC STOPPED: Total RC PDF is empty or failed to generate.');
            throw new HighwayManualSendException(
                'Total Rate Confirmation PDF could not be generated.'
            );
        }
        
        System.debug('TOTAL RC PDF SIZE: ' + pdfBlob.size());
        
        String boundary = '----HighwayBoundary' + String.valueOf(Datetime.now().getTime());
        String externalId = String.valueOf(loadId) + '-TOTAL-' + String.valueOf(Datetime.now().getTime());
        
        MultipartFormBuilder form = new MultipartFormBuilder(boundary);
        
        form.addField('rate_confirmation[carrier_id]', load.Highway_Carrier_ID__c);
        form.addField('rate_confirmation[external_id]', externalId);
        form.addField('rate_confirmation[external_load_id]', String.valueOf(loadId));
        form.addField('rate_confirmation[broker_load_owner_email]', brokerEmail);
        
        // Total RC must always be sent with targeted_emails.
        form.addField(
            'rate_confirmation[targeted_emails][]',
            targetEmailToSend.trim()
        );
        
        form.addFile(
            'rate_confirmation[attachments][]',
            'rate_confirmation_total.pdf',
            'application/pdf',
            pdfBlob
        );
        
        HttpRequest req = new HttpRequest();
        
        // Sandbox
        //req.setEndpoint('https://staging.highway.com/core/connect/external_api/v1/rate_confirmations');
        
        // Production
         req.setEndpoint(HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/rate_confirmations');
        
        req.setMethod('POST');
        
        String authHeader = HighwayAPIService.HIGHWAY_API_KEY;
        
        if (!String.isBlank(authHeader) && !authHeader.startsWith('Bearer ')) {
            authHeader = 'Bearer ' + authHeader;
        }
        
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', 'application/json');
        req.setBodyAsBlob(form.build());
        req.setTimeout(60000);
        
        HttpResponse res = new Http().send(req);
        
        System.debug('Total RC Response Code: ' + res.getStatusCode());
        System.debug('Total RC Response Body: ' + res.getBody());
        System.debug('Total RC Target Email: ' + targetEmailToSend);
        System.debug('Total RC External Id: ' + externalId);
        System.debug('Total RC PDF Size: ' + pdfBlob.size());
        
        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(Id = loadId);
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            String rcStatus = 'Pending';
            
            if (String.isNotBlank(res.getBody())) {
                try {
                    Map<String, Object> result =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    
                    if (result.containsKey('id') && result.get('id') != null) {
                        loadUpdate.Highway_TotalRC_ID__c = String.valueOf(result.get('id'));
                    }
                    
                    if (result.containsKey('status') && result.get('status') != null) {
                        Map<String, String> statuses = new Map<String, String>{
                            'pending'   => 'Pending',
                                'sent'      => 'Sent',
                                'viewed'    => 'Viewed',
                                'signed'    => 'Signed',
                                'delivered' => 'Delivered',
                                'rejected'  => 'Rejected',
                                'voided'    => 'Voided',
                                'accepted'  => 'Accepted'
                                };
                                    
                                    String apiStatus = String.valueOf(result.get('status')).toLowerCase();
                        rcStatus = statuses.containsKey(apiStatus)
                            ? statuses.get(apiStatus)
                            : apiStatus;
                    }
                    
                } catch (Exception ex) {
                    System.debug('Unable to parse Total RC response body: ' + ex.getMessage());
                }
            }
            
            loadUpdate.Highway_Target_Email__c = targetEmailToSend.trim();
            loadUpdate.Highway_TotalRC_Sent__c = true;
            loadUpdate.Highway_TotalRC_Status__c = rcStatus;
            
        } else {
            loadUpdate.Highway_TotalRC_Sent__c = false;
            loadUpdate.Highway_TotalRC_Status__c = 'Error';
            
            update loadUpdate;
            
            throw new HighwayManualSendException(
                'Highway returned an error. Status code: ' +
                res.getStatusCode() +
                '. Body: ' +
                res.getBody()
            );
        }
        
        update loadUpdate;
        
        attachGeneratedTotalRcDebugPdf(loadId, pdfBlob);
    }
    
    public static void sendTotalRateConfirmationNow(Id loadId) {
        sendTotalRateConfirmationNow(loadId, null);
        
        
    }
    
    private class MultipartFormBuilder {
        private  final String CRLF = '\r\n';
        
        private String boundary;
        private List<String> hexParts = new List<String>();
        
        public MultipartFormBuilder(String boundary) {
            this.boundary = boundary;
        }
        
        public void addField(String name, String value) {
            String safeValue = value == null ? '' : value;
            
            String part =
                '--' + boundary + CRLF +
                'Content-Disposition: form-data; name="' + name + '"' + CRLF +
                CRLF +
                safeValue + CRLF;
            
            hexParts.add(EncodingUtil.convertToHex(Blob.valueOf(part)));
        }
        
        public void addFile(String name, String filename, String contentType, Blob body) {
            String header =
                '--' + boundary + CRLF +
                'Content-Disposition: form-data; name="' + name + '"; filename="' + filename + '"' + CRLF +
                'Content-Type: ' + contentType + CRLF +
                CRLF;
            
            hexParts.add(EncodingUtil.convertToHex(Blob.valueOf(header)));
            hexParts.add(EncodingUtil.convertToHex(body));
            hexParts.add(EncodingUtil.convertToHex(Blob.valueOf(CRLF)));
        }
        
        public Blob build() {
            String closing = '--' + boundary + '--' + CRLF;
            hexParts.add(EncodingUtil.convertToHex(Blob.valueOf(closing)));
            
            String fullHex = '';
            for (String hexPart : hexParts) {
                fullHex += hexPart;
            }
            
            return EncodingUtil.convertFromHex(fullHex);
        }
    }
    
    private static void attachGeneratedTotalRcDebugPdf(Id loadId, Blob pdfBlob) {
        if (loadId == null || pdfBlob == null || pdfBlob.size() == 0) {
            System.debug('TOTAL RC debug attach skipped. Empty PDF blob.');
            return;
        }
        
        try {
            ContentVersion cv = new ContentVersion(
                Title = 'Total_RateCon_' + Datetime.now().format('yyyyMMdd_HHmmss'),
                PathOnClient = 'Total_RateCon.pdf',
                VersionData = pdfBlob,
                FirstPublishLocationId = loadId
            );
            
            insert cv;
            
            System.debug('TOTAL RC debug PDF attached to Load: ' + loadId);
            System.debug('TOTAL RC debug PDF size: ' + pdfBlob.size());
        } catch (Exception e) {
            System.debug('TOTAL RC debug PDF attach error: ' + e.getMessage());
        }
    }
    
    // ============= new helpers for cancel/active =============
    private static Boolean isTerminalRcStatus(String status) {
        if (String.isBlank(status)) {
            return false;
        }
        
        Set<String> terminalStatuses = new Set<String>{
                'Cancelled',
                'Canceled',
                'Voided',
                'Rejected',
                'Error'
                };
                    
                    return terminalStatuses.contains(status.trim());
    }
        
    private static Boolean hasActiveTotalRc(FreightTM__Load__c load) {
        if (load == null) {
            return false;
        }
        
        Boolean hasTotalRcMarker =
            load.Highway_TotalRC_Sent__c == true ||
            String.isNotBlank(load.Highway_TotalRC_ID__c);
        
        if (!hasTotalRcMarker) {
            return false;
        }
        
        return !isTerminalRcStatus(load.Highway_TotalRC_Status__c);
    }
    
    @AuraEnabled
    public static String cancelExistingRateConfirmationsForNewCarrier(Id loadId) {
        if (loadId == null) {
            throw new HighwayManualSendException('Load Id is missing.');
        }
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            Highway_RC_ID__c,
            Highway_RC_Status__c,
            Highway_TotalRC_ID__c,
            Highway_TotalRC_Status__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        
        if (loads.isEmpty()) {
            throw new HighwayManualSendException('Load not found.');
        }
        
        FreightTM__Load__c load = loads[0];
        
        Boolean cancelledSomething = false;
        
        if (
            String.isNotBlank(load.Highway_RC_ID__c) &&
            !isTerminalRcStatus(load.Highway_RC_Status__c)
        ) {
            cancelHighwayRateConfirmation(load.Highway_RC_ID__c);
            cancelledSomething = true;
        }
        
        if (
            String.isNotBlank(load.Highway_TotalRC_ID__c) &&
            !isTerminalRcStatus(load.Highway_TotalRC_Status__c)
        ) {
            cancelHighwayRateConfirmation(load.Highway_TotalRC_ID__c);
            cancelledSomething = true;
        }
        
        resetHighwayRateConfirmationFieldsForNewCarrier(loadId);
        
        return cancelledSomething
            ? 'Existing Highway rate confirmation(s) cancelled and load reset successfully.'
            : 'No active Highway rate confirmation found. Load reset successfully.';
    }
    
    private static void cancelHighwayRateConfirmation(String rcId) {
        if (String.isBlank(rcId)) {
            return;
        }
        
        HttpRequest req = new HttpRequest();
        
        // Sandbox
        //req.setEndpoint(
        //    'https://staging.highway.com/core/connect/external_api/v1/rate_confirmations/' +/
        //    EncodingUtil.urlEncode(rcId, 'UTF-8')
        //);
        
        // Production
         req.setEndpoint(
             HighwayAPIService.getBaseUrl() + '/core/connect/external_api/v1/rate_confirmations/' +
             EncodingUtil.urlEncode(rcId, 'UTF-8')
         );
        
        req.setMethod('PATCH');
        
        String authHeader = HighwayAPIService.HIGHWAY_API_KEY;
        
        if (!String.isBlank(authHeader) && !authHeader.startsWith('Bearer ')) {
            authHeader = 'Bearer ' + authHeader;
        }
        
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        
        req.setBody(JSON.serialize(new Map<String, Object>{
            'rate_confirmation' => new Map<String, Object>{
                'status' => 'cancelled'
                    }
        }));
        
        req.setTimeout(60000);
        
        HttpResponse res = new Http().send(req);
        
        System.debug('Cancel Highway RC Id: ' + rcId);
        System.debug('Cancel Highway RC Response Code: ' + res.getStatusCode());
        System.debug('Cancel Highway RC Response Body: ' + res.getBody());
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new HighwayManualSendException(
                'Could not cancel Highway Rate Confirmation. Status code: ' +
                res.getStatusCode() +
                '. Body: ' +
                res.getBody()
            );
        }
    }
    
    private static void resetHighwayRateConfirmationFieldsForNewCarrier(Id loadId) {
        if (loadId == null) {
            throw new HighwayManualSendException('Load Id is missing.');
        }
        
        update new FreightTM__Load__c(
            Id = loadId,
            
            Highway_RC_ID__c = null,
            Highway_RC_Status__c = 'Cancelled',
            
            Highway_TotalRC_ID__c = null,
            Highway_TotalRC_Sent__c = false,
            Highway_TotalRC_Status__c = 'Cancelled',
            
            Highway_Target_Email__c = null
        );
    }
    
    // =========== Extract Carrier emails =============================
    private static String extractCarrierContactEmails(Map<String, Object> result) {
        if (result == null) {
            return null;
        }
        
        Object contactInfoObj = result.get('contact_information');
        
        if (!(contactInfoObj instanceof Map<String, Object>)) {
            return null;
        }
        
        Map<String, Object> contactInfo = (Map<String, Object>) contactInfoObj;
        Object emailAddressesObj = contactInfo.get('email_addresses');
        
        if (!(emailAddressesObj instanceof List<Object>)) {
            return null;
        }
        
        List<Object> emailAddresses = (List<Object>) emailAddressesObj;
        
        Set<String> uniqueEmailsLower = new Set<String>();
        List<String> finalEmails = new List<String>();
        
        for (Object emailObj : emailAddresses) {
            if (!(emailObj instanceof Map<String, Object>)) {
                continue;
            }
            
            Map<String, Object> emailRow = (Map<String, Object>) emailObj;
            
            if (!emailRow.containsKey('value') || emailRow.get('value') == null) {
                continue;
            }
            
            String email = String.valueOf(emailRow.get('value')).trim();
            
            if (String.isBlank(email)) {
                continue;
            }
            
            String emailLower = email.toLowerCase();
            
            if (!looksLikeEmail(emailLower)) {
                continue;
            }
            
            if (!uniqueEmailsLower.contains(emailLower)) {
                uniqueEmailsLower.add(emailLower);
                finalEmails.add(email);
            }
        }
        
        if (finalEmails.isEmpty()) {
            return null;
        }
        
        return String.join(finalEmails, ', ');
    }
    
    private static Boolean looksLikeEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        
        Pattern p = Pattern.compile('(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$');
        Matcher m = p.matcher(value.trim());
        return m.matches();
    }
    
    
    
    
    
}
