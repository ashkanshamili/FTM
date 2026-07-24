public without sharing class DriverPortalActionHandler {

    private static final String ACTION_PORTAL_OPENED =
        'PORTAL_OPENED';

    private static final String ACTION_ISSUE_REPORTED =
        'ISSUE_REPORTED';

    private static final String ACTION_SIGNATURE_AT_SHIPPING =
        'SIGNATURE_AT_SHIPPING';

    private static final String ACTION_SIGNATURE_IN_TRANSIT =
        'SIGNATURE_IN_TRANSIT_TO_DELIVERY';

    private static final String ACTION_SIGNATURE_AT_RECEIVING =
        'SIGNATURE_AT_RECEIVING';

    private static final String ACTION_SIGNATURE_DELIVERED =
        'SIGNATURE_DELIVERED';


    public static void handleAfterInsert(
        List<Driver_Portal_Action__e> events
    ) {
        if (events == null || events.isEmpty()) {
            return;
        }

        System.debug(
            'DriverPortalActionHandler received events: ' +
            events.size()
        );

        Map<Id, Driver_Portal_Action__e> latestStatusEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();

        Map<Id, Driver_Portal_Action__e> portalOpenedEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();

        Map<Id, Driver_Portal_Action__e> latestIssueEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();

        Map<Id, Driver_Portal_Action__e> latestSignatureEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();

        Set<Id> loadIds = new Set<Id>();


        /*
         * Classify incoming platform events.
         */
        for (Driver_Portal_Action__e evt : events) {
            System.debug(
                'Driver Portal Event: ' +
                'Load_Id__c=' + evt.Load_Id__c +
                ', Action_Name__c=' + evt.Action_Name__c +
                ', Token_Hash__c=' + evt.Token_Hash__c +
                ', Event_Time__c=' + evt.Event_Time__c +
                ', Issue_Type__c=' + evt.Issue_Type__c +
                ', Notes__c=' + evt.Notes__c
            );

            if (String.isBlank(evt.Load_Id__c)) {
                System.debug(
                    'Skipped event because Load_Id__c is blank.'
                );
                continue;
            }

            Id loadId;

            try {
                loadId = (Id) evt.Load_Id__c;
            } catch (Exception ex) {
                System.debug(
                    'Invalid Load Id from Driver Portal Action: ' +
                    evt.Load_Id__c
                );
                continue;
            }

            loadIds.add(loadId);

            if (isStatusAction(evt.Action_Name__c)) {
                putLatestEvent(
                    latestStatusEventByLoadId,
                    loadId,
                    evt
                );

            } else if (
                evt.Action_Name__c == ACTION_PORTAL_OPENED
            ) {
                putLatestEvent(
                    portalOpenedEventByLoadId,
                    loadId,
                    evt
                );

            } else if (
                evt.Action_Name__c == ACTION_ISSUE_REPORTED
            ) {
                putLatestEvent(
                    latestIssueEventByLoadId,
                    loadId,
                    evt
                );

            } else if (
                isSignatureAction(evt.Action_Name__c)
            ) {
                putLatestEvent(
                    latestSignatureEventByLoadId,
                    loadId,
                    evt
                );

            } else {
                System.debug(
                    'Skipped unsupported action: ' +
                    evt.Action_Name__c
                );
            }
        }

        if (loadIds.isEmpty()) {
            System.debug(
                'No valid Load Ids found from Driver Portal events.'
            );
            return;
        }


        /*
         * Retrieve all fields needed to validate and update the Loads.
         */
        Map<Id, FreightTM__Load__c> existingLoads =
            new Map<Id, FreightTM__Load__c>([
                SELECT
                    Id,
                    Driver_Portal_Token_Hash__c,
                    Driver_Portal_Active__c,
                    Driver_Portal_Last_Opened__c,

                    FreightTM__Status__c,
                    FreightTM__Pickup_Arrival__c,
                    FreightTM__Pickup_Departure__c,
                    FreightTM__Delivery_Arrival__c,
                    FreightTM__Delivery_Departure__c,

                    FreightTM__Driver_Remarks__c,
                    Exception_Reason__c,

                    At_Shipping_Signature__c,
                    In_Transit_to_Delivery_Signature__c,
                    At_Receiving_Signature__c,
                    Delivered_Signature__c

                FROM FreightTM__Load__c
                WHERE Id IN :loadIds
            ]);

        Map<Id, FreightTM__Load__c> updatesByLoadId =
            new Map<Id, FreightTM__Load__c>();


        /*
         * Process status actions.
         */
        for (Id loadId : latestStatusEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt =
                latestStatusEventByLoadId.get(loadId);

            FreightTM__Load__c existingLoad =
                existingLoads.get(loadId);

            if (
                !isValidEventForLoad(
                    existingLoad,
                    evt,
                    loadId,
                    'status update'
                )
            ) {
                continue;
            }

            FreightTM__Load__c updateLoad =
                buildStatusLoadUpdate(
                    existingLoad,
                    evt.Action_Name__c,
                    evt.Event_Time__c
                );

            if (updateLoad != null) {
                mergeLoadUpdate(
                    updatesByLoadId,
                    updateLoad
                );
            }
        }


        /*
         * Process portal-opened actions.
         */
        for (Id loadId : portalOpenedEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt =
                portalOpenedEventByLoadId.get(loadId);

            FreightTM__Load__c existingLoad =
                existingLoads.get(loadId);

            if (
                !isValidEventForLoad(
                    existingLoad,
                    evt,
                    loadId,
                    'portal opened update'
                )
            ) {
                continue;
            }

            Datetime openedAt =
                evt.Event_Time__c != null
                    ? evt.Event_Time__c
                    : System.now();

            FreightTM__Load__c updateLoad =
                new FreightTM__Load__c(
                    Id = loadId,
                    Driver_Portal_Last_Opened__c = openedAt
                );

            mergeLoadUpdate(
                updatesByLoadId,
                updateLoad
            );
        }


        /*
         * Process issue actions.
         */
        for (Id loadId : latestIssueEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt =
                latestIssueEventByLoadId.get(loadId);

            FreightTM__Load__c existingLoad =
                existingLoads.get(loadId);

            if (
                !isValidEventForLoad(
                    existingLoad,
                    evt,
                    loadId,
                    'issue update'
                )
            ) {
                continue;
            }

            FreightTM__Load__c updateLoad =
                buildIssueLoadUpdate(
                    existingLoad,
                    evt
                );

            if (updateLoad != null) {
                mergeLoadUpdate(
                    updatesByLoadId,
                    updateLoad
                );
            }
        }


        /*
         * Process signature actions.
         */
        for (
            Id loadId :
            latestSignatureEventByLoadId.keySet()
        ) {
            Driver_Portal_Action__e evt =
                latestSignatureEventByLoadId.get(loadId);

            FreightTM__Load__c existingLoad =
                existingLoads.get(loadId);

            if (
                !isValidEventForLoad(
                    existingLoad,
                    evt,
                    loadId,
                    'signature update'
                )
            ) {
                continue;
            }

            FreightTM__Load__c updateLoad =
                buildSignatureLoadUpdate(
                    existingLoad,
                    evt.Action_Name__c
                );

            if (updateLoad != null) {
                mergeLoadUpdate(
                    updatesByLoadId,
                    updateLoad
                );
            }
        }


        /*
         * Perform one bulk update for all Load changes.
         */
        if (updatesByLoadId.isEmpty()) {
            System.debug(
                'No Loads to update from Driver Portal events.'
            );
            return;
        }

        List<FreightTM__Load__c> loadsToUpdate =
            new List<FreightTM__Load__c>(
                updatesByLoadId.values()
            );

        Database.SaveResult[] results =
            Database.update(
                loadsToUpdate,
                false
            );

        for (
            Integer index = 0;
            index < results.size();
            index++
        ) {
            Database.SaveResult result =
                results[index];

            FreightTM__Load__c loadUpdate =
                loadsToUpdate[index];

            if (result.isSuccess()) {
                System.debug(
                    'Driver portal Load update succeeded: ' +
                    loadUpdate.Id
                );
                continue;
            }

            for (Database.Error err : result.getErrors()) {
                System.debug(
                    'Driver portal Load update failed for ' +
                    loadUpdate.Id +
                    ': ' +
                    err.getStatusCode() +
                    ' - ' +
                    err.getMessage()
                );
            }
        }
    }


    /*
     * Retain the newest event when more than one action of the same
     * category arrives for a Load in the same trigger transaction.
     */
    private static void putLatestEvent(
        Map<Id, Driver_Portal_Action__e> eventMap,
        Id loadId,
        Driver_Portal_Action__e incomingEvent
    ) {
        Driver_Portal_Action__e existingEvent =
            eventMap.get(loadId);

        if (existingEvent == null) {
            eventMap.put(loadId, incomingEvent);
            return;
        }

        Datetime existingTime =
            existingEvent.Event_Time__c;

        Datetime incomingTime =
            incomingEvent.Event_Time__c;

        if (
            existingTime == null ||
            (
                incomingTime != null &&
                incomingTime >= existingTime
            )
        ) {
            eventMap.put(loadId, incomingEvent);
        }
    }


    /*
     * Confirm that the event belongs to the Load and was generated
     * using the currently active portal token.
     */
    private static Boolean isValidEventForLoad(
        FreightTM__Load__c existingLoad,
        Driver_Portal_Action__e evt,
        Id loadId,
        String actionLabel
    ) {
        if (existingLoad == null) {
            System.debug(
                'Skipped ' +
                actionLabel +
                '. Load not found: ' +
                loadId
            );
            return false;
        }

        if (existingLoad.Driver_Portal_Active__c != true) {
            System.debug(
                'Skipped ' +
                actionLabel +
                '. Portal inactive for Load: ' +
                loadId
            );
            return false;
        }

        if (
            String.isBlank(evt.Token_Hash__c) ||
            evt.Token_Hash__c !=
                existingLoad.Driver_Portal_Token_Hash__c
        ) {
            System.debug(
                'Skipped ' +
                actionLabel +
                '. Token mismatch for Load: ' +
                loadId +
                '. Event token hash=' +
                evt.Token_Hash__c +
                ', Load token hash=' +
                existingLoad.Driver_Portal_Token_Hash__c
            );
            return false;
        }

        return true;
    }


    private static Boolean isStatusAction(
        String actionName
    ) {
        return actionName == 'ARRIVED_PICKUP' ||
            actionName == 'DEPARTED_PICKUP' ||
            actionName == 'ARRIVED_DELIVERY' ||
            actionName == 'DELIVERED';
    }


    private static Boolean isSignatureAction(
        String actionName
    ) {
        return actionName ==
                ACTION_SIGNATURE_AT_SHIPPING ||
            actionName ==
                ACTION_SIGNATURE_IN_TRANSIT ||
            actionName ==
                ACTION_SIGNATURE_AT_RECEIVING ||
            actionName ==
                ACTION_SIGNATURE_DELIVERED;
    }


    /*
     * Build changes for normal load-status events.
     */
    private static FreightTM__Load__c
        buildStatusLoadUpdate(
            FreightTM__Load__c existingLoad,
            String actionName,
            Datetime eventTime
        ) {
        Datetime actionTime =
            eventTime != null
                ? eventTime
                : System.now();

        FreightTM__Load__c updateLoad =
            new FreightTM__Load__c(
                Id = existingLoad.Id
            );

        if (actionName == 'ARRIVED_PICKUP') {
            updateLoad.FreightTM__Pickup_Arrival__c =
                actionTime;

            updateLoad.FreightTM__Status__c =
                'At Shipping';

        } else if (actionName == 'DEPARTED_PICKUP') {
            updateLoad.FreightTM__Pickup_Departure__c =
                actionTime;

            updateLoad.FreightTM__Status__c =
                'In Transit to Delivery';

        } else if (actionName == 'ARRIVED_DELIVERY') {
            updateLoad.FreightTM__Delivery_Arrival__c =
                actionTime;

            updateLoad.FreightTM__Status__c =
                'At Receiving';

        } else if (actionName == 'DELIVERED') {
            updateLoad.FreightTM__Delivery_Departure__c =
                actionTime;

            updateLoad.FreightTM__Status__c =
                'Delivered';

            /*
             * Leave the portal active if the driver still needs to
             * upload a POD or signature after delivery.
             *
             * To close it immediately, uncomment:
             *
             * updateLoad.Driver_Portal_Active__c = false;
             */

        } else {
            return null;
        }

        return updateLoad;
    }


    /*
     * Build changes from an issue report.
     */
    private static FreightTM__Load__c
        buildIssueLoadUpdate(
            FreightTM__Load__c existingLoad,
            Driver_Portal_Action__e evt
        ) {
        String exceptionReason =
            cleanText(
                evt.Issue_Type__c,
                100
            );

        String driverRemarks =
            cleanText(
                evt.Notes__c,
                255
            );

        if (
            String.isBlank(exceptionReason) &&
            String.isBlank(driverRemarks)
        ) {
            System.debug(
                'Skipped issue update because both ' +
                'Issue_Type__c and Notes__c are blank.'
            );
            return null;
        }

        FreightTM__Load__c updateLoad =
            new FreightTM__Load__c(
                Id = existingLoad.Id
            );

        if (!String.isBlank(exceptionReason)) {
            updateLoad.Exception_Reason__c =
                exceptionReason;
        }

        if (!String.isBlank(driverRemarks)) {
            updateLoad.FreightTM__Driver_Remarks__c =
                driverRemarks;
        }

        return updateLoad;
    }


    /*
     * Set the appropriate signature checkbox.
     *
     * These actions are published by saveSignature() after the
     * signature file has been saved or versioned.
     */
    private static FreightTM__Load__c
        buildSignatureLoadUpdate(
            FreightTM__Load__c existingLoad,
            String actionName
        ) {
        FreightTM__Load__c updateLoad =
            new FreightTM__Load__c(
                Id = existingLoad.Id
            );

        if (
            actionName ==
            ACTION_SIGNATURE_AT_SHIPPING
        ) {
            /*
             * Avoid unnecessary DML when already checked.
             */
            if (
                existingLoad.At_Shipping_Signature__c ==
                true
            ) {
                return null;
            }

            updateLoad.At_Shipping_Signature__c =
                true;

        } else if (
            actionName ==
            ACTION_SIGNATURE_IN_TRANSIT
        ) {
            if (
                existingLoad
                    .In_Transit_to_Delivery_Signature__c ==
                true
            ) {
                return null;
            }

            updateLoad
                .In_Transit_to_Delivery_Signature__c =
                true;

        } else if (
            actionName ==
            ACTION_SIGNATURE_AT_RECEIVING
        ) {
            if (
                existingLoad.At_Receiving_Signature__c ==
                true
            ) {
                return null;
            }

            updateLoad.At_Receiving_Signature__c =
                true;

        } else if (
            actionName ==
            ACTION_SIGNATURE_DELIVERED
        ) {
            if (
                existingLoad.Delivered_Signature__c ==
                true
            ) {
                return null;
            }

            updateLoad.Delivered_Signature__c =
                true;

        } else {
            return null;
        }

        return updateLoad;
    }


    private static String cleanText(
        String value,
        Integer maxLength
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        String cleanValue =
            value.trim();

        if (
            maxLength != null &&
            cleanValue.length() > maxLength
        ) {
            cleanValue =
                cleanValue.substring(
                    0,
                    maxLength
                );
        }

        return cleanValue;
    }


    /*
     * Merge multiple requested changes for the same Load into one
     * partial sObject update.
     */
    private static void mergeLoadUpdate(
        Map<Id, FreightTM__Load__c> updatesByLoadId,
        FreightTM__Load__c incomingUpdate
    ) {
        if (
            incomingUpdate == null ||
            incomingUpdate.Id == null
        ) {
            return;
        }

        FreightTM__Load__c existingUpdate =
            updatesByLoadId.get(
                incomingUpdate.Id
            );

        if (existingUpdate == null) {
            updatesByLoadId.put(
                incomingUpdate.Id,
                incomingUpdate
            );
            return;
        }

        Map<String, Object> populatedFields =
            incomingUpdate
                .getPopulatedFieldsAsMap();

        for (
            String fieldName :
            populatedFields.keySet()
        ) {
            if (fieldName == 'Id') {
                continue;
            }

            existingUpdate.put(
                fieldName,
                populatedFields.get(fieldName)
            );
        }

        updatesByLoadId.put(
            existingUpdate.Id,
            existingUpdate
        );
    }
}



/*public without sharing class DriverPortalActionHandler {
    
    private static final String ACTION_PORTAL_OPENED = 'PORTAL_OPENED';
    private static final String ACTION_ISSUE_REPORTED = 'ISSUE_REPORTED';
    
    public static void handleAfterInsert(List<Driver_Portal_Action__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        System.debug('DriverPortalActionHandler received events: ' + events.size());
        
        Map<Id, Driver_Portal_Action__e> latestStatusEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();
        
        Map<Id, Driver_Portal_Action__e> portalOpenedEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();
        
        Map<Id, Driver_Portal_Action__e> latestIssueEventByLoadId =
            new Map<Id, Driver_Portal_Action__e>();
        
        Set<Id> loadIds = new Set<Id>();
        
        for (Driver_Portal_Action__e evt : events) {
            System.debug(
                'Driver Portal Event: Load_Id__c=' + evt.Load_Id__c +
                ', Action_Name__c=' + evt.Action_Name__c +
                ', Token_Hash__c=' + evt.Token_Hash__c +
                ', Event_Time__c=' + evt.Event_Time__c +
                ', Issue_Type__c=' + evt.Issue_Type__c +
                ', Notes__c=' + evt.Notes__c
            );
            
            if (String.isBlank(evt.Load_Id__c)) {
                System.debug('Skipped event because Load_Id__c is blank.');
                continue;
            }
            
            Id loadId;
            
            try {
                loadId = (Id) evt.Load_Id__c;
            } catch (Exception e) {
                System.debug('Invalid Load Id from Driver Portal Action: ' + evt.Load_Id__c);
                continue;
            }
            
            loadIds.add(loadId);
            
            if (isStatusAction(evt.Action_Name__c)) {
                latestStatusEventByLoadId.put(loadId, evt);
            } else if (evt.Action_Name__c == ACTION_PORTAL_OPENED) {
                portalOpenedEventByLoadId.put(loadId, evt);
            } else if (evt.Action_Name__c == ACTION_ISSUE_REPORTED) {
                latestIssueEventByLoadId.put(loadId, evt);
            } else {
                System.debug('Skipped event because action is not supported: ' + evt.Action_Name__c);
            }
        }
        
        if (loadIds.isEmpty()) {
            System.debug('No valid Load Ids found from Driver Portal events.');
            return;
        }
        
        Map<Id, FreightTM__Load__c> existingLoads =
            new Map<Id, FreightTM__Load__c>([
                SELECT Id,
                Driver_Portal_Token_Hash__c,
                Driver_Portal_Active__c,
                FreightTM__Status__c,
                FreightTM__Pickup_Arrival__c,
                FreightTM__Pickup_Departure__c,
                FreightTM__Delivery_Arrival__c,
                FreightTM__Delivery_Departure__c,
                FreightTM__Driver_Remarks__c,
                Exception_Reason__c
                FROM FreightTM__Load__c
                WHERE Id IN :loadIds
            ]);
        
        Map<Id, FreightTM__Load__c> updatesByLoadId =
            new Map<Id, FreightTM__Load__c>();
        
        for (Id loadId : latestStatusEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt = latestStatusEventByLoadId.get(loadId);
            FreightTM__Load__c existingLoad = existingLoads.get(loadId);
            
            if (!isValidEventForLoad(existingLoad, evt, loadId, 'status update')) {
                continue;
            }
            
            FreightTM__Load__c updateLoad =
                buildStatusLoadUpdate(existingLoad, evt.Action_Name__c, evt.Event_Time__c);
            
            if (updateLoad != null) {
                mergeLoadUpdate(updatesByLoadId, updateLoad);
            }
        }
        
        for (Id loadId : portalOpenedEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt = portalOpenedEventByLoadId.get(loadId);
            FreightTM__Load__c existingLoad = existingLoads.get(loadId);
            
            if (!isValidEventForLoad(existingLoad, evt, loadId, 'portal opened update')) {
                continue;
            }
            
            FreightTM__Load__c updateLoad = new FreightTM__Load__c(
                Id = loadId,
                Driver_Portal_Last_Opened__c = evt.Event_Time__c != null
                ? evt.Event_Time__c
                : System.now()
            );
            
            mergeLoadUpdate(updatesByLoadId, updateLoad);
        }
        
        for (Id loadId : latestIssueEventByLoadId.keySet()) {
            Driver_Portal_Action__e evt = latestIssueEventByLoadId.get(loadId);
            FreightTM__Load__c existingLoad = existingLoads.get(loadId);
            
            if (!isValidEventForLoad(existingLoad, evt, loadId, 'issue update')) {
                continue;
            }
            
            FreightTM__Load__c updateLoad =
                buildIssueLoadUpdate(existingLoad, evt);
            
            if (updateLoad != null) {
                mergeLoadUpdate(updatesByLoadId, updateLoad);
            }
        }
        
        if (!updatesByLoadId.isEmpty()) {
            List<FreightTM__Load__c> loadsToUpdate =
                new List<FreightTM__Load__c>(updatesByLoadId.values());
            
            Database.SaveResult[] results = Database.update(loadsToUpdate, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('Driver portal Load update succeeded: ' + loadsToUpdate[i].Id);
                } else {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            'Driver portal Load update failed for ' +
                            loadsToUpdate[i].Id +
                            ': ' +
                            err.getStatusCode() +
                            ' - ' +
                            err.getMessage()
                        );
                    }
                }
            }
        } else {
            System.debug('No Loads to update from Driver Portal events.');
        }
    }
    
    private static Boolean isValidEventForLoad(
        FreightTM__Load__c existingLoad,
        Driver_Portal_Action__e evt,
        Id loadId,
        String actionLabel
    ) {
        if (existingLoad == null) {
            System.debug('Skipped ' + actionLabel + '. Load not found: ' + loadId);
            return false;
        }
        
        if (existingLoad.Driver_Portal_Active__c != true) {
            System.debug('Skipped ' + actionLabel + '. Portal inactive for Load: ' + loadId);
            return false;
        }
        
        if (
            String.isBlank(evt.Token_Hash__c) ||
            evt.Token_Hash__c != existingLoad.Driver_Portal_Token_Hash__c
        ) {
            System.debug(
                'Skipped ' + actionLabel + '. Token mismatch for Load: ' + loadId +
                '. Event token hash=' + evt.Token_Hash__c +
                ', Load token hash=' + existingLoad.Driver_Portal_Token_Hash__c
            );
            return false;
        }
        
        return true;
    }
    
    private static Boolean isStatusAction(String actionName) {
        return actionName == 'ARRIVED_PICKUP' ||
            actionName == 'DEPARTED_PICKUP' ||
            actionName == 'ARRIVED_DELIVERY' ||
            actionName == 'DELIVERED';
    }
    
    
    private static FreightTM__Load__c buildStatusLoadUpdate(
        FreightTM__Load__c existingLoad,
        String actionName,
        Datetime eventTime
    ) {
        Datetime actionTime = eventTime != null
            ? eventTime
            : System.now();
        
        FreightTM__Load__c updateLoad =
            new FreightTM__Load__c(Id = existingLoad.Id);
        
        if (actionName == 'ARRIVED_PICKUP') {
            updateLoad.FreightTM__Pickup_Arrival__c = actionTime;
            updateLoad.FreightTM__Status__c = 'At Shipping';
            
        } else if (actionName == 'DEPARTED_PICKUP') {
            updateLoad.FreightTM__Pickup_Departure__c = actionTime;
            updateLoad.FreightTM__Status__c = 'In Transit to Delivery';
            
        } else if (actionName == 'ARRIVED_DELIVERY') {
            updateLoad.FreightTM__Delivery_Arrival__c = actionTime;
            updateLoad.FreightTM__Status__c = 'At Receiving';
            
        } else if (actionName == 'DELIVERED') {
            updateLoad.FreightTM__Delivery_Departure__c = actionTime;
            updateLoad.FreightTM__Status__c = 'Delivered';
            //updateLoad.Driver_Portal_Active__c = false;
            
        } else {
            return null;
        }
        
        return updateLoad;
    }
    
    private static FreightTM__Load__c buildIssueLoadUpdate(
        FreightTM__Load__c existingLoad,
        Driver_Portal_Action__e evt
    ) {
        String exceptionReason = cleanText(evt.Issue_Type__c, 100);
        String driverRemarks = cleanText(evt.Notes__c, 255);
        
        if (String.isBlank(exceptionReason) && String.isBlank(driverRemarks)) {
            System.debug('Skipped issue update because both Issue_Type__c and Notes__c are blank.');
            return null;
        }
        
        FreightTM__Load__c updateLoad =
            new FreightTM__Load__c(Id = existingLoad.Id);
        
        if (!String.isBlank(exceptionReason)) {
            updateLoad.Exception_Reason__c = exceptionReason;
        }
        
        if (!String.isBlank(driverRemarks)) {
            updateLoad.FreightTM__Driver_Remarks__c = driverRemarks;
        }
        
        return updateLoad;
    }
    
    private static String cleanText(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        
        String cleanValue = value.trim();
        
        if (maxLength != null && cleanValue.length() > maxLength) {
            cleanValue = cleanValue.substring(0, maxLength);
        }
        
        return cleanValue;
    }
    
    private static void mergeLoadUpdate(
        Map<Id, FreightTM__Load__c> updatesByLoadId,
        FreightTM__Load__c incomingUpdate
    ) {
        if (incomingUpdate == null || incomingUpdate.Id == null) {
            return;
        }
        
        FreightTM__Load__c existingUpdate = updatesByLoadId.get(incomingUpdate.Id);
        
        if (existingUpdate == null) {
            updatesByLoadId.put(incomingUpdate.Id, incomingUpdate);
            return;
        }
        
        Map<String, Object> populatedFields =
            incomingUpdate.getPopulatedFieldsAsMap();
        
        for (String fieldName : populatedFields.keySet()) {
            if (fieldName == 'Id') {
                continue;
            }
            
            existingUpdate.put(fieldName, populatedFields.get(fieldName));
        }
        
        updatesByLoadId.put(existingUpdate.Id, existingUpdate);
    }
}*/