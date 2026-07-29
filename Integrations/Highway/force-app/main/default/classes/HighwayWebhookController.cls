@RestResource(urlMapping='/highway/webhook/*')
global without sharing class HighwayWebhookController {
    
    @TestVisible
    private static String webhookSecretOverride;
    
    private static final Map<String, String> STATUS_MAP = new Map<String, String>{
        'pending'   => 'Pending',
            'sent'      => 'Sent',
            'viewed'    => 'Viewed',
            'signed'    => 'Signed',
            'delivered' => 'Delivered',
            'rejected'  => 'Rejected',
            'voided'    => 'Voided',
            'accepted'  => 'Accepted',
            'cancelled' => 'Cancelled',
            'canceled'  => 'Cancelled'
            };
                
                @HttpPost
                global static void handleWebhook() {
                    RestRequest  req = RestContext.request;
                    RestResponse res = RestContext.response;
                    res.addHeader('Content-Type', 'application/json');
                    
                    try {
                        // ── 1. Validate token ─────────────────────────────────
                        String token         = req.params.get('token');
                        String expectedToken = getWebhookSecret();
                        if (String.isBlank(token) || token != expectedToken) {
                            res.statusCode   = 401;
                            res.responseBody = Blob.valueOf('{"error":"Unauthorized"}');
                            return;
                        }
                        
                        // ── 2. Parse payload ──────────────────────────────────
                        if (req.requestBody == null) {
                            res.statusCode   = 400;
                            res.responseBody = Blob.valueOf('{"error":"Empty body"}');
                            return;
                        }
                        
                        String rawBody = req.requestBody.toString();
                        System.debug('Highway webhook raw body: ' + rawBody);
                        
                        Map<String, Object> payload =
                            (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
                        
                        // ── 3. Extract fields ─────────────────────────────────
                        String externalLoadId = payload.containsKey('external_load_id')
                            ? String.valueOf(payload.get('external_load_id'))
                            : null;
                        
                        if (String.isBlank(externalLoadId) && payload.containsKey('external_id')) {
                            String raw = String.valueOf(payload.get('external_id'));
                            externalLoadId = raw.contains('-') ? raw.substringBefore('-') : raw;
                        }
                        
                        String rcStatus  = String.valueOf(payload.get('status'));
                        String rcId      = payload.containsKey('id')
                            ? String.valueOf(payload.get('id'))
                            : null;
                        // Extract the accepted/signed activity email
                        String highwayTargetEmail = extractAcceptedActivityEmail(payload, rcStatus);
                        
                        
                        // Extract PDF url and filename
                        String pdfUrl      = null;
                        String pdfFilename = null;
                        Object pdfObj      = payload.get('digital_signature_pdf');
                        if (pdfObj instanceof Map<String, Object>) {
                            Map<String, Object> pdf = (Map<String, Object>) pdfObj;
                            pdfUrl      = (String) pdf.get('url');
                            pdfFilename = (String) pdf.get('filename');
                        }
                        
                        if (String.isBlank(externalLoadId) || String.isBlank(rcStatus)) {
                            res.statusCode   = 400;
                            res.responseBody = Blob.valueOf('{"error":"Missing required fields"}');
                            return;
                        }
                        
                        // ── 4. Resolve status ─────────────────────────────────
                        String mappedStatus = STATUS_MAP.get(rcStatus.toLowerCase());
                        if (mappedStatus == null) {
                            mappedStatus = rcStatus;
                        }
                        
                        // ── 5. Find Load ──────────────────────────────────────
                        List<FreightTM__Load__c> loads = [
                            SELECT Id, Highway_RC_ID__c,Highway_TotalRC_ID__c,Highway_TotalRC_Sent__c,Highway_TotalRC_Status__c
                            FROM FreightTM__Load__c
                            WHERE Id = :externalLoadId
                            LIMIT 1
                        ];
                        
                        if (loads.isEmpty()) {
                            res.statusCode   = 200;
                            res.responseBody = Blob.valueOf('{"status":"not_found","external_load_id":"' + externalLoadId + '"}');
                            return;
                        }
                        
                        Id loadId = loads[0].Id;
                        
                        // ── 6. Update Load record ─────────────────────────────
                        FreightTM__Load__c existingLoad = loads[0];
                        
                        Boolean webhookIsForTotalRc =
                            String.isNotBlank(rcId) &&
                            String.isNotBlank(existingLoad.Highway_TotalRC_ID__c) &&
                            rcId == existingLoad.Highway_TotalRC_ID__c;
                        
                        Boolean firstRcAcceptedOrSigned =
                            rcStatus != null &&
                            (
                                rcStatus.toLowerCase() == 'accepted' ||
                                rcStatus.toLowerCase() == 'signed'
                            );
                        
                        Boolean shouldSendTotalRc = false;
                        
                        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(Id = loadId);
                        
                       
                        if (webhookIsForTotalRc) {
                            // This webhook belongs to the second / Total RC.
                            if (String.isNotBlank(rcId)) {
                                loadUpdate.Highway_TotalRC_ID__c = rcId;
                            }
                            
                            loadUpdate.Highway_TotalRC_Status__c = mappedStatus;
                            
                            if (
                                mappedStatus == 'Cancelled' ||
                                mappedStatus == 'Canceled' ||
                                mappedStatus == 'Voided' ||
                                mappedStatus == 'Rejected' ||
                                mappedStatus == 'Error'
                            ) {
                                loadUpdate.Highway_TotalRC_Sent__c = false;
                            } else {
                                loadUpdate.Highway_TotalRC_Sent__c = true;
                            }
                            
                        } else {
                            // This webhook belongs to the first / normal RC.
                            loadUpdate.Highway_RC_Status__c = mappedStatus;
                            
                            if (String.isNotBlank(rcId)) {
                                loadUpdate.Highway_RC_ID__c = rcId;
                            }
                            
                            if (
                                String.isNotBlank(highwayTargetEmail) &&
                                firstRcAcceptedOrSigned
                            ) {
                                loadUpdate.Highway_Target_Email__c = highwayTargetEmail.trim();
                            }
                            
                            Boolean existingTotalRcIsTerminal =
                                existingLoad.Highway_TotalRC_Status__c == 'Cancelled' ||
                                existingLoad.Highway_TotalRC_Status__c == 'Canceled' ||
                                existingLoad.Highway_TotalRC_Status__c == 'Voided' ||
                                existingLoad.Highway_TotalRC_Status__c == 'Rejected' ||
                                existingLoad.Highway_TotalRC_Status__c == 'Error';
                            
                           
                            shouldSendTotalRc =
                                firstRcAcceptedOrSigned &&
                                String.isNotBlank(highwayTargetEmail) &&
                                (
                                    existingLoad.Highway_TotalRC_Sent__c != true ||
                                    existingTotalRcIsTerminal
                                ) &&
                                (
                                    String.isBlank(existingLoad.Highway_TotalRC_ID__c) ||
                                    existingTotalRcIsTerminal
                                );
                            
                            if (shouldSendTotalRc) {
                                loadUpdate.Highway_TotalRC_Sent__c = false;
                                loadUpdate.Highway_TotalRC_Status__c = 'Ready to Send';
                            }
                        }
                        
                        update loadUpdate;
                        
                        if (shouldSendTotalRc) {
                           // HighwayLoadService.sendTotalRateConfirmationAfterFirstAcceptedAsync(loadId);
                            HighwayLoadService.markTotalRateConfirmationReady(loadId);
                        }
                        
                        // ── 7. Attach PDF if present ──────────────────────────
                        // Must run after DML — callout after DML not allowed in same context
                        // So we use @future to download and attach
                        if (String.isNotBlank(pdfUrl) && String.isNotBlank(pdfFilename)) {
                            attachPdfAsync(loadId, pdfUrl, pdfFilename);
                        }
                        
                        res.statusCode   = 200;
                        res.responseBody = Blob.valueOf(
                            '{"status":"ok","load_id":"' + loadId + '","rc_status":"' + mappedStatus + '"}'
                        );
                        
                    } catch (JSONException je) {
                        System.debug('JSON error: ' + je.getMessage());
                        res.statusCode   = 400;
                        res.responseBody = Blob.valueOf('{"error":"Invalid JSON payload"}');
                    } catch (Exception e) {
                        System.debug('Error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
                        res.statusCode   = 500;
                        res.responseBody = Blob.valueOf('{"error":"Internal server error"}');
                    }
                }
    
    private static String extractAcceptedActivityEmail(Map<String, Object> payload, String rcStatus) {
        if (payload == null || String.isBlank(rcStatus)) {
            return null;
        }
        
        Object activitiesObj = payload.get('recent_rate_confirmation_activities');
        if (!(activitiesObj instanceof List<Object>)) {
            System.debug('recent_rate_confirmation_activities not found or not a list.');
            return null;
        }
        
        List<Object> activities = (List<Object>) activitiesObj;
        String desiredType = rcStatus.toLowerCase(); // accepted or signed
        
        // 1) Exact match to webhook status
        for (Object actObj : activities) {
            if (!(actObj instanceof Map<String, Object>)) {
                continue;
            }
            
            Map<String, Object> activity = (Map<String, Object>) actObj;
            String isType = activity.get('is_type') == null
                ? null
                : String.valueOf(activity.get('is_type')).toLowerCase();
            
            if (isType != desiredType) {
                continue;
            }
            
            Map<String, Object> userMap = activity.get('user') instanceof Map<String, Object>
                ? (Map<String, Object>) activity.get('user')
                : null;
            
            if (userMap != null && userMap.containsKey('email') && userMap.get('email') != null) {
                String email = String.valueOf(userMap.get('email')).trim();
                if (looksLikeEmail(email)) {
                    System.debug('Highway target email found from activity type ' + desiredType + ': ' + email);
                    return email;
                }
            }
        }
        
        // 2) Fallback for accepted: prefer signed if accepted activity is not present
        if (desiredType == 'accepted') {
            for (Object actObj : activities) {
                if (!(actObj instanceof Map<String, Object>)) {
                    continue;
                }
                
                Map<String, Object> activity = (Map<String, Object>) actObj;
                String isType = activity.get('is_type') == null
                    ? null
                    : String.valueOf(activity.get('is_type')).toLowerCase();
                
                //if (isType != 'signed' || isType != 'terms_accepted') {
                //    continue;
                //}
                Set<String> fallbackTypes = new Set<String>{ 'signed', 'terms_accepted', 'accepted' };
                    
                    if (!fallbackTypes.contains(isType)) {
                        continue;
                    }
                
                Map<String, Object> userMap = activity.get('user') instanceof Map<String, Object>
                    ? (Map<String, Object>) activity.get('user')
                    : null;
                
                if (userMap != null && userMap.containsKey('email') && userMap.get('email') != null) {
                    String email = String.valueOf(userMap.get('email')).trim();
                    if (looksLikeEmail(email)) {
                        System.debug('Highway target email fallback from signed activity: ' + email);
                        return email;
                    }
                }
            }
        }
        
        System.debug('No matching accepted/signed activity email found.');
        return null;
    }
    
    private static Boolean looksLikeEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        
        Pattern p = Pattern.compile('(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$');
        Matcher m = p.matcher(value.trim());
        return m.matches();
    }
    
    @future(callout=true)
    private static void attachPdfAsync(Id loadId, String pdfUrl, String pdfFilename) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(pdfUrl);
            req.setMethod('GET');
            req.setTimeout(120000);
            req.setHeader('Accept', '');
            
            HttpResponse res = new Http().send(req);
            
            if (res.getStatusCode() != 200) {
                System.debug('PDF download failed: ' + res.getStatusCode());
                return;
            }
            
            Blob fileBody = res.getBodyAsBlob();
            
            // Delete existing RC PDF for this load
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :loadId
            ];
            
            if (!existingLinks.isEmpty()) {
                Set<Id> docIds = new Set<Id>();
                for (ContentDocumentLink l : existingLinks) {
                    docIds.add(l.ContentDocumentId);
                }
                
                List<ContentVersion> existing = [
                    SELECT ContentDocumentId, Title
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :docIds
                    AND IsLatest = true
                    AND Title LIKE '%rate_confirmation%'
                ];
                
                if (!existing.isEmpty()) {
                    Set<Id> toDelete = new Set<Id>();
                    for (ContentVersion cvOld : existing) {
                        toDelete.add(cvOld.ContentDocumentId);
                    }
                    delete [SELECT Id FROM ContentDocument WHERE Id IN :toDelete];
                }
            }
            
            // Insert file directly onto the Load
            ContentVersion cv = new ContentVersion(
                Title                  = pdfFilename,
                PathOnClient           = pdfFilename,
                VersionData            = fileBody,
                FirstPublishLocationId = loadId
            );
            insert cv;
            
            System.debug('PDF attached successfully to Load: ' + loadId);
            
        } catch (Exception e) {
            System.debug('attachPdfAsync error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }
    }
    private static String getWebhookSecret() {
        if (Test.isRunningTest() && webhookSecretOverride != null) {
            return webhookSecretOverride;
        }
        
        try {
            List<Highway_Config__mdt> configs = [
                SELECT Webhook_Secret__c
                FROM Highway_Config__mdt
                LIMIT 1
            ];
            if (!configs.isEmpty()) {
                return configs[0].Webhook_Secret__c;
            }
        } catch (Exception e) {
            System.debug('getWebhookSecret error: ' + e.getMessage());
        }
        return null;
    }
}
