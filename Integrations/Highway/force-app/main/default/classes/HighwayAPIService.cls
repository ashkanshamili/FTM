public class HighwayAPIService {
    private static final Integer MIN_YEAR = 1900;
    
    public static String HIGHWAY_API_KEY;
    public static String HIGHWAY_API_URL;
    public static String CARRIER_API_URL;
    public static String ENVIRONMENT = 'sandbox';
    public static String MARK_PROCESSED_URL;
    public static String ONBOARDING_PACKETS_URL;
    public static String MARK_ONBOARDING_PROCESSED_URL;
    public static String RESET_PACKET_URL;
    public static String RESET_ALERT_URL;
    public static String SYNC_CARRIER_URL;
    public static String ONBOARDING_PACKETS_URL_id;
    
    // This block runs once when the class loads to set up the API settings
    static {
        loadApiConfig();
    }
    
     public static String getBaseUrl() {
        return ENVIRONMENT == 'prod'
            ? 'https://highway.com'
            : 'https://staging.highway.com';
    }

    // Syncs carrier data in the background without marking it as processed.
     // Great for a one-time sync when you just need the data updated.
    @future(callout=true)
    public static void syncCarriers() {
        try {
            // Get current page from custom setting
            // Pages__c pageSetting = Pages__c.getInstance();
            // Integer currentPage = pageSetting.CurrentPage__c != null ? Integer.valueOf(pageSetting.CurrentPage__c) : 1;
            
            // Construct endpoint with current page
            String endpoint = getBaseUrl() + '/core/connect/external_api/v1/carriers/full_rules_and_insurance_updates?per_page=50&page=1';
            System.debug('Sync: ' + endpoint);
            
            HttpResponse response = makeApiCall(endpoint, 'GET');
            
            if (response.getStatusCode() == 200) {
                IdsWrapper ids = extractCarrierIds(response.getBody(), true);
                
                if (!ids.carrierIds.isEmpty()) {
                    System.debug('Processing with carrier IDs: ' + ids.carrierIds);
                    System.enqueueJob(new HighwayProcessCarriersQueueable(ids.carrierIds, ids.objectIds, false, false));
                    
                    // Increment CurrentPage__c for the next call
                    // pageSetting.CurrentPage__c = currentPage + 1;
                } else {
                    System.debug('No more carriers to sync. Resetting to page 1');
                    // Reset CurrentPage__c to 1 if no data is returned
                    // pageSetting.CurrentPage__c = 1;
                }
                
                // Update the custom setting
                // update pageSetting;
            } else {
                handleApiError('Alerts API', response);
            }
            
            // System.debug('Completed syncing carriers for page ' + currentPage);
        } catch (Exception e) {
            System.debug('Error in syncCarriers: ' + e.getMessage());
        }
    }
    

     // Fetches and processes alerts, marking them as processed afterward.
    @future(callout=true)
    public static void fetchAndProcessAlerts() {
        try {
            String endpoint = HIGHWAY_API_URL + '?per_page=50&page=';
            System.debug('Fetching Alerts from endpoint: ' + endpoint);
            
            HttpResponse response = makeApiCall(endpoint, 'GET');
            
            if (response.getStatusCode() != 200) {
                handleApiError('Alerts API', response);
            }
            
            IdsWrapper ids = extractCarrierIds(response.getBody(), false);
            
            if (ids.carrierIds.isEmpty()) {
                System.debug('No alerts found ' );
            }
            
            System.debug('Processing ' +' with carrier IDs: ' + ids.carrierIds);
            System.enqueueJob(new HighwayProcessCarriersQueueable(ids.carrierIds, ids.objectIds, false, false));
            System.debug('Completed fetching and processing alerts.');
        } catch (Exception e) {
            System.debug('Error in fetchAndProcessAlerts: ' + e.getMessage());
        }
    }
    
    @future(callout=true)
    public static void fetchAndProcessOnboardingPackets() {
        try {
            String endpoint = ONBOARDING_PACKETS_URL + '?per_page=50&page=';
            System.debug('Fetching Onboarding Packets from endpoint: ' + endpoint);
            
            HttpResponse response = makeApiCall(endpoint, 'GET');
            
            if (response.getStatusCode() != 200) {
                handleApiError('Onboarding Packets API', response);
            }
            
            IdsWrapper ids = extractCarrierIds(response.getBody(), false);
            
            // Break out of loop if there are no more records returned
            if (ids.carrierIds.isEmpty()) {
                System.debug('No onboarding packets found ');
            }
            
            System.debug('Processing page ' + ' with carrier IDs: ' + ids.carrierIds);
            System.enqueueJob(new HighwayProcessCarriersQueueable(ids.carrierIds, ids.objectIds, true, true));
            System.debug('Completed fetching and processing onboarding packets.');
        } catch (Exception e) {
            System.debug('Error in fetchAndProcessOnboardingPackets: ' + e.getMessage());
        }
    }
    
    public static void processCarriersBulk(List<Integer> carrierIds, List<Integer> objectIds, Boolean isOnboarding) {
        try {
            
            System.debug('=== HIGHWAY API SERVICE - processCarriersBulk ENTERED ===');
            // Maps to track carriers and their DOT numbers
            Map<Integer, FreightTM__Carrier__c> carriersToUpsert = new Map<Integer, FreightTM__Carrier__c>();
            Map<Integer, String> carrierDOTNumbers = new Map<Integer, String>();
            Map<Integer, List<Object>> contractsToProcessLater = new Map<Integer, List<Object>>();
            
            // Fetch and process each carrier or onboarding packet
            for (Integer i = 0; i < carrierIds.size(); i++) {
                Integer carrierId = carrierIds[i];
                Integer objectId = (objectIds != null && i < objectIds.size()) ? objectIds[i] : null;
                
                FreightTM__Carrier__c carrier = new FreightTM__Carrier__c();
                
                if (isOnboarding && objectId != null) {
                    String packetEndpoint = ONBOARDING_PACKETS_URL + '/' + objectId;
                    HttpResponse packetResponse = makeApiCall(packetEndpoint, 'GET');
                    
                    if (packetResponse.getStatusCode() == 200) {
                        // Parse the response and extract contracts
                        Map<String, Object> parsedData = parseOnboardingPacketResponseAndExtractContracts(packetResponse.getBody(), carrier);
                        carrier = (FreightTM__Carrier__c) parsedData.get('carrier');
                        List<Object> contracts = (List<Object>) parsedData.get('contracts');
                        
                        System.debug('Carrier with onboarding packet data for ID ' + objectId + ': ' + carrier);
                        
                        // Store contracts for processing after upsert
                        if (contracts != null && !contracts.isEmpty()) {
                            contractsToProcessLater.put(carrierId, contracts);
                        }
                    } else {
                        System.debug('Failed to fetch onboarding packet details for ID ' + objectId + ': ' + packetResponse.getStatusCode());
                        continue;
                    }
                } 
                else {
                    String carrierEndpoint = CARRIER_API_URL + carrierId;
                    HttpResponse carrierResponse = makeApiCall(carrierEndpoint, 'GET');
                    
                    if (carrierResponse.getStatusCode() == 200) {
                        carrier = parseCarrierResponse(carrierResponse.getBody());
                        if (carrier == null) {
                            System.debug('Failed to parse carrier details for ID ' + carrierId);
                            continue;
                        }
                        System.debug('Carrier with API data for ID ' + carrierId + ': ' + carrier);
                    } else {
                        System.debug('Failed to fetch carrier details for ID ' + carrierId + ': ' + carrierResponse.getStatusCode());
                        continue;
                    }
                }
                                // ──────────────────────────────────────────────────────────────
                // NEW: Get creator from connection_invitations (replaces old contract mapping)
                // Runs for both onboarding and regular carriers
                // Uses the Highway carrierId we already have
                // ──────────────────────────────────────────────────────────────
                try {
                    String invitationEndpoint = getBaseUrl() + '/core/connect/external_api/v1/connection_invitations?q[carrier_id_eq]=' + carrierId;
                    System.debug('Fetching connection invitation for Highway carrier ID ' + carrierId + ' → ' + invitationEndpoint);

                    HttpResponse invResponse = makeApiCall(invitationEndpoint, 'GET');

                    if (invResponse.getStatusCode() == 200) {
                        List<Object> invitations = (List<Object>) JSON.deserializeUntyped(invResponse.getBody());

                        if (invitations != null && !invitations.isEmpty()) {
                            Map<String, Object> invitation = (Map<String, Object>) invitations[0];
                            List<Object> invitorsList = (List<Object>) invitation.get('invitors');

                            if (invitorsList != null && !invitorsList.isEmpty()) {
                                Map<String, Object> invitor = (Map<String, Object>) invitorsList[0];

                                String firstName = (String) invitor.get('first_name');
                                String lastName  = (String) invitor.get('last_name');
                                String email     = (String) invitor.get('email');

                                if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
                                    carrier.Create_User__c = firstName + ' ' + lastName;
                                } else if (String.isNotBlank(firstName)) {
                                    carrier.Create_User__c = firstName;
                                }
                                carrier.Create_User_Email__c = email;

                                System.debug('Set Create_User__c / Create_User_Email__c from invitor → ' +
                                    carrier.Create_User__c + ' / ' + carrier.Create_User_Email__c);
                            } else {
                                System.debug('No invitors found for carrierId ' + carrierId);
                            }
                        } else {
                            System.debug('No invitations returned for carrierId ' + carrierId);
                        }
                    } else {
                        System.debug('Invitation API returned ' + invResponse.getStatusCode() + ' for carrierId ' + carrierId);
                    }
                } catch (Exception e) {
                    System.debug('Exception while fetching invitation for carrierId ' + carrierId + ': ' + e.getMessage());
                }
                // ──────────────────────────────────────────────────────────────
                
                String dot = carrier.FreightTM__USDOT_Number__c;
                if (String.isBlank(dot)) {
                    System.debug('Skipping carrier with no valid DOT number for carrierId: ' + carrierId);
                    continue;
                }
                
                carriersToUpsert.put(carrierId, carrier);
                carrierDOTNumbers.put(carrierId, dot);
            }
            
            // Query existing carriers by DOT numbers
            Map<String, Id> existingCarrierByDOT = new Map<String, Id>();
            if (!carrierDOTNumbers.isEmpty()) {
                Set<String> dots = new Set<String>(carrierDOTNumbers.values());
                List<FreightTM__Carrier__c> dotMatches = [
                    SELECT Id, FreightTM__USDOT_Number__c
                    FROM FreightTM__Carrier__c
                    WHERE FreightTM__USDOT_Number__c IN :dots
                ];
                
                for (FreightTM__Carrier__c existing : dotMatches) {
                    existingCarrierByDOT.put(existing.FreightTM__USDOT_Number__c, existing.Id);
                }
            }
            
            // Assign IDs from existing carriers and prepare for upsert
            List<FreightTM__Carrier__c> carriersToDML = new List<FreightTM__Carrier__c>();
            for (Integer carrierId : carriersToUpsert.keySet()) {
                FreightTM__Carrier__c carrier = carriersToUpsert.get(carrierId);
                String dot = carrierDOTNumbers.get(carrierId);
                
                if (dot != null && existingCarrierByDOT.containsKey(dot)) {
                    carrier.Id = existingCarrierByDOT.get(dot);
                    System.debug('Matched existing carrier by DOT for ID ' + carrierId + ': ' + carrier.Id);
                }
                
                carriersToDML.add(carrier);
            }
            
            // Perform bulk upsert
            if (!carriersToDML.isEmpty()) {
                try {
                    upsert carriersToDML;
                    System.debug('Upserted ' + carriersToDML.size() + ' carriers');
                    
                    // Now process contracts for carriers that were upserted
                    processContractsAfterUpsert(carriersToDML, carrierDOTNumbers, contractsToProcessLater);
                } catch (DmlException e) {
                    System.debug('Error upserting carriers: ' + e.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('Error in processCarriersBulk: ' + e.getMessage());
        }
        
        System.debug('=== HIGHWAY API SERVICE - processCarriersBulk COMPLETED ===');
    }
    

     // Turns the API response into a carrier object for Salesforce.
     // Maps JSON fields to the right spots in our carrier record.
    public static FreightTM__Carrier__c parseCarrierResponse(String responseBody) {
        try {
            Map<String, Object> carrierData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            FreightTM__Carrier__c carrier = new FreightTM__Carrier__c();
            
            carrier.Name = (String) carrierData.get('legal_name');
            carrier.FreightTM__MC_MX_FF_Number__c = (String) carrierData.get('mc_number');
            carrier.FreightTM__USDOT_Number__c = (String) carrierData.get('dot_number');
            
            // Look for SCAC code in the identifiers list
            List<Object> identifiers = (List<Object>) carrierData.get('identifiers');
            if (identifiers != null && !identifiers.isEmpty()) {
                for (Object identifierObj : identifiers) {
                    Map<String, Object> identifier = (Map<String, Object>) identifierObj;
                    if (identifier.get('is_type') == 'SCAC') {
                        carrier.FreightTM__SCAC_Code__c = (String) identifier.get('value');
                        break;
                    }
                }
            }
            
            Map<String, Object> insurance = (Map<String, Object>) carrierData.get('insurance');
            if (insurance != null) {
                List<Object> policies = (List<Object>) insurance.get('insurance_policies');
                if (policies != null && !policies.isEmpty()) {
                    for (Object policyObj : policies) {
                        Map<String, Object> policy = (Map<String, Object>) policyObj;
                        String type = (String) policy.get('is_type');
                        string status = (string) policy.get('status');
                        String effectiveDateStr = (String) policy.get('effective_date');
                        String expirationDateStr = (String) policy.get('expiration_date');
                        String limitStr = (String) policy.get('limit');
                        
                        if ('commercial_general_liability'.equals(type)) {
                            if (effectiveDateStr != null) {
                                carrier.Liability_Insurance_Effective__c = Date.valueOf(effectiveDateStr);
                            }
                            if (expirationDateStr != null) {
                                carrier.FreightTM__Liability_Insurance_Expiration__c = Date.valueOf(expirationDateStr);
                            }
                            if (limitStr != null) {
                                carrier.FreightTM__Liability_Insurance_Amount__c = Decimal.valueOf(limitStr).intValue();
                            }
                        } else if ('motor_truck_cargo'.equals(type)) {
                            carrier.General_Status__c = status ;
                            if (effectiveDateStr != null) {
                                carrier.General_Insurance_Effective__c = Date.valueOf(effectiveDateStr);
                            }
                            if (expirationDateStr != null) {
                                carrier.General_Insurance_Expiration__c = Date.valueOf(expirationDateStr);
                            }
                            if (limitStr != null) {
                                carrier.General_Insurance_Amount__c = Decimal.valueOf(limitStr).intValue();
                            }
                        }
                    }
                }
            }
            
            // Grab the physical and mailing addresses if they exist
            List<Object> addresses = (List<Object>) carrierData.get('addresses');
            if (addresses != null && !addresses.isEmpty()) {
                Map<String, Object> latestPhysicalAddress = null;
                Map<String, Object> latestMailingAddress = null;
                DateTime latestPhysicalSeen = null;
                DateTime latestMailingSeen = null;
                
                for (Object addrObj : addresses) {
                    Map<String, Object> address = (Map<String, Object>) addrObj;
                    String addressType = (String) address.get('is_type');
                    String lastSeenStr = (String) address.get('last_seen_at');
                    DateTime lastSeen = null;
                    
                    if (lastSeenStr != null) {
                        try {
                            lastSeen = DateTime.valueOf(lastSeenStr); // Convert string to DateTime
                        } catch (Exception e) {
                            System.debug('Invalid date format: ' + lastSeenStr);
                        }
                    }
                    
                    if (addressType == 'physical') {
                        if (latestPhysicalSeen == null || (lastSeen != null && lastSeen.getTime() > latestPhysicalSeen.getTime())) {
                            latestPhysicalSeen = lastSeen;
                            latestPhysicalAddress = address;
                        }
                    } else if (addressType == 'mailing') {
                        if (latestMailingSeen == null || (lastSeen != null && lastSeen.getTime() > latestMailingSeen.getTime())) {
                            latestMailingSeen = lastSeen;
                            latestMailingAddress = address;
                        }
                    }
                }
                
                // Assign the latest physical address
                if (latestPhysicalAddress != null) {
                    carrier.FreightTM__Address__c = formatAddress((String) latestPhysicalAddress.get('street1'));
                    carrier.FreightTM__City__c = (String) latestPhysicalAddress.get('city');
                    carrier.FreightTM__State_Province__c = (String) latestPhysicalAddress.get('state');
                    carrier.FreightTM__Zip_Code__c = (String) latestPhysicalAddress.get('postal_code');
                    String countryCode = (String) latestPhysicalAddress.get('nationality');
                    carrier.FreightTM__Country__c = countryCode != null ? getFullCountryName(countryCode) : null;
                }
                
                // Assign the latest mailing address
                if (latestMailingAddress != null) {
                    carrier.Mailing_Address__c = formatAddress((String) latestMailingAddress.get('street1'));
                    carrier.Mailing_City__c = (String) latestMailingAddress.get('city');
                    carrier.Mailing_State__c = (String) latestMailingAddress.get('state');
                    carrier.Mailing_Zip__c = (String) latestMailingAddress.get('postal_code');
                }
            }
            
            // Get contact details
            Map<String, Object> contactInfo = (Map<String, Object>) carrierData.get('contact_information');
            if (contactInfo != null) {
                // Handle dispatch_contact (primary contact)
                Map<String, Object> dispatchContact = (Map<String, Object>) contactInfo.get('dispatch_contact');
                if (dispatchContact != null) {
                    carrier.FreightTM__Primary_Contact__c = (String) dispatchContact.get('name');
                    carrier.FreightTM__Phone__c = (String) dispatchContact.get('phone');
                    carrier.FreightTM__Email__c = (String) dispatchContact.get('email_address');
                }
                
                // Handle line_item_contacts ( billing, claims)
                List<Object> lineItemContacts = (List<Object>) contactInfo.get('line_item_contacts');
                if (lineItemContacts != null && !lineItemContacts.isEmpty()) {
                    for (Object contactObj : lineItemContacts) {
                        Map<String, Object> contact = (Map<String, Object>) contactObj;
                        String contactType = (String) contact.get('is_type');
                        String name = (String) contact.get('name');
                        String phone = (String) contact.get('phone');
                        String email = (String) contact.get('email_address');
                        
                        if ('billing'.equals(contactType)) {
                            carrier.Contact_Name_1__c = name;
                            carrier.Contact_Phone_1__c = phone;
                            carrier.Contact_Email_1__c = email;
                        } else if ('claims'.equals(contactType)) {
                            carrier.Contact_Name_2__c = name;
                            carrier.Contact_Phone_2__c = phone;
                            carrier.Contact_Email_2__c = email;
                        }
                    }
                }
            }
            
            // Look for EIN in tax_identifiers
            List<Object> taxIdentifiers = (List<Object>) carrierData.get('tax_identifiers');
            if (taxIdentifiers != null && !taxIdentifiers.isEmpty()) {
                for (Object taxIdObj : taxIdentifiers) {
                    Map<String, Object> taxId = (Map<String, Object>) taxIdObj;
                    if ('ein'.equals(taxId.get('is_type'))) {
                        carrier.FreightTM__Federal_ID__c = (String) taxId.get('value');
                        break;
                    }
                }
            }
            
            return carrier;
        } catch (Exception e) {
            System.debug('Couldn\u2019t parse the carrier response: ' + e.getMessage());
            throw e;
        }
    }
    
     // Parses the onboarding packet response and extracts both carrier data and contracts.
     // Returns a map with 'carrier' and 'contracts' keys.
    public static Map<String, Object> parseOnboardingPacketResponseAndExtractContracts(String responseBody, FreightTM__Carrier__c carrier) {
        Map<String, Object> packetData;
        Map<String, Object> result = new Map<String, Object>();
        List<Object> executedContracts = new List<Object>();
        
        try {
            packetData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            // Step 1: Extract the payment term type
            String types = null;
            if (packetData.containsKey('payment_term') && packetData.get('payment_term') instanceof Map<String, Object>) {
                Map<String, Object> paymentTerm = (Map<String, Object>) packetData.get('payment_term');
                if (paymentTerm.containsKey('is_type')) {
                    types = (String) paymentTerm.get('is_type');
                }
            }
            
            // Process carrier_detail for carrier information
            if (packetData.containsKey('carrier_detail') && packetData.get('carrier_detail') instanceof Map<String, Object>) {
                Map<String, Object> carrierData = (Map<String, Object>) packetData.get('carrier_detail');
                
                // Extract MC and DOT numbers and legal name
                String mc = 'MC'+(String) carrierData.get('mc_number');
                String dot = (String) carrierData.get('dot_number');
                String name = (String) carrierData.get('legal_name');
                
                if (name != null) {
                    carrier.Name = name;
                } else {
                    System.debug('Warning: legal_name is missing in carrier_detail');
                }
                
                if (mc != null) {
                    carrier.FreightTM__MC_MX_FF_Number__c = mc;
                } else {
                    System.debug('Warning: mc_number is missing in carrier_detail');
                }
                
                if (dot != null) {
                    dot = dot.replaceFirst('^0+', '');
                    carrier.FreightTM__USDOT_Number__c = dot;
                } else {
                    System.debug('Warning: dot_number is missing in carrier_detail');
                }
                
                // Look for SCAC code in the identifiers list
                List<Object> identifiers = (List<Object>) carrierData.get('identifiers');
                if (identifiers != null && !identifiers.isEmpty()) {
                    for (Object identifierObj : identifiers) {
                        Map<String, Object> identifier = (Map<String, Object>) identifierObj;
                        if (identifier.get('is_type') == 'SCAC') {
                            carrier.FreightTM__SCAC_Code__c = (String) identifier.get('value');
                            break;
                        }
                    }
                }
                
                Map<String, Object> insurance = (Map<String, Object>) carrierData.get('insurance');
                if (insurance != null) {
                    List<Object> policies = (List<Object>) insurance.get('insurance_policies');
                    if (policies != null && !policies.isEmpty()) {
                        for (Object policyObj : policies) {
                            Map<String, Object> policy = (Map<String, Object>) policyObj;
                            String type = (String) policy.get('is_type');
                            String status = (String) policy.get('status');
                            String effectiveDateStr = (String) policy.get('effective_date');
                            String expirationDateStr = (String) policy.get('expiration_date');
                            String limitStr = (String) policy.get('limit');
                            
                            if ('commercial_general_liability'.equals(type)) {
                                Date effectiveDate = parseDateSafely(effectiveDateStr, MIN_YEAR);
                                if (effectiveDate == null && effectiveDateStr != null) {
                                    System.debug('Setting Liability_Insurance_Effective__c to null for invalid or old date: ' + effectiveDateStr);
                                }
                                carrier.Liability_Insurance_Effective__c = effectiveDate;
                                
                                Date expirationDate = parseDateSafely(expirationDateStr, MIN_YEAR);
                                if (expirationDate == null && expirationDateStr != null) {
                                    System.debug('Setting FreightTM__Liability_Insurance_Expiration__c to null for invalid or old date: ' + expirationDateStr);
                                }
                                carrier.FreightTM__Liability_Insurance_Expiration__c = expirationDate;
                                
                                if (limitStr != null) {
                                    carrier.FreightTM__Liability_Insurance_Amount__c = Decimal.valueOf(limitStr).intValue();
                                }
                            } else if ('motor_truck_cargo'.equals(type)) {
                                carrier.General_Status__c = status;
                                
                                Date effectiveDate = parseDateSafely(effectiveDateStr, MIN_YEAR);
                                if (effectiveDate == null && effectiveDateStr != null) {
                                    System.debug('Setting General_Insurance_Effective__c to null for invalid or old date: ' + effectiveDateStr);
                                }
                                carrier.General_Insurance_Effective__c = effectiveDate;
                                
                                Date expirationDate = parseDateSafely(expirationDateStr, MIN_YEAR);
                                if (expirationDate == null && expirationDateStr != null) {
                                    System.debug('Setting General_Insurance_Expiration__c to null for invalid or old date: ' + expirationDateStr);
                                }
                                carrier.General_Insurance_Expiration__c = expirationDate;
                                
                                if (limitStr != null) {
                                    carrier.General_Insurance_Amount__c = Decimal.valueOf(limitStr).intValue();
                                }
                            }
                        }
                    }
                }
                
                // Grab the physical and mailing addresses if they exist
                List<Object> addresses = (List<Object>) carrierData.get('addresses');
                if (addresses != null && !addresses.isEmpty()) {
                    Map<String, Object> latestPhysicalAddress = null;
                    Map<String, Object> latestMailingAddress = null;
                    DateTime latestPhysicalSeen = null;
                    DateTime latestMailingSeen = null;
                    
                    for (Object addrObj : addresses) {
                        Map<String, Object> address = (Map<String, Object>) addrObj;
                        String addressType = (String) address.get('is_type');
                        String lastSeenStr = (String) address.get('last_seen_at');
                        DateTime lastSeen = null;
                        
                        if (lastSeenStr != null) {
                            try {
                                lastSeen = DateTime.valueOf(lastSeenStr);
                            } catch (Exception e) {
                                System.debug('Invalid date format: ' + lastSeenStr);
                            }
                        }
                        
                        if (addressType == 'physical') {
                            if (latestPhysicalSeen == null || (lastSeen != null && lastSeen.getTime() > latestPhysicalSeen.getTime())) {
                                latestPhysicalSeen = lastSeen;
                                latestPhysicalAddress = address;
                            }
                        } else if (addressType == 'mailing') {
                            if (latestMailingSeen == null || (lastSeen != null && lastSeen.getTime() > latestMailingSeen.getTime())) {
                                latestMailingSeen = lastSeen;
                                latestMailingAddress = address;
                            }
                        }
                    }
                    
                    // Assign the latest physical address
                    if (latestPhysicalAddress != null) {
                        carrier.FreightTM__Address__c = formatAddress((String) latestPhysicalAddress.get('street1'));
                        carrier.FreightTM__City__c = (String) latestPhysicalAddress.get('city');
                        carrier.FreightTM__State_Province__c = (String) latestPhysicalAddress.get('state');
                        carrier.FreightTM__Zip_Code__c = (String) latestPhysicalAddress.get('postal_code');
                        String countryCode = (String) latestPhysicalAddress.get('nationality');
                        carrier.FreightTM__Country__c = countryCode != null ? getFullCountryName(countryCode) : null;
                    }
                    
                    // Assign the latest mailing address
                    if (latestMailingAddress != null) {
                        carrier.Mailing_Address__c = formatAddress((String) latestMailingAddress.get('street1'));
                        carrier.Mailing_City__c = (String) latestMailingAddress.get('city');
                        carrier.Mailing_State__c = (String) latestMailingAddress.get('state');
                        carrier.Mailing_Zip__c = (String) latestMailingAddress.get('postal_code');
                    }
                }
                
                // Get contact details
                Map<String, Object> contactInfo = (Map<String, Object>) carrierData.get('contact_information');
                if (contactInfo != null) {
                    // Handle dispatch_contact (primary contact)
                    Map<String, Object> dispatchContact = (Map<String, Object>) contactInfo.get('dispatch_contact');
                    if (dispatchContact != null) {
                        String primaryName = (String) dispatchContact.get('name');
                        carrier.FreightTM__Primary_Contact__c = getFirstTwoWords(primaryName);
                        carrier.FreightTM__Phone__c = (String) dispatchContact.get('phone');
                        carrier.FreightTM__Email__c = (String) dispatchContact.get('email_address');
                    }
                    
                    // Handle line_item_contacts (billing, claims)
                    List<Object> lineItemContacts = (List<Object>) contactInfo.get('line_item_contacts');
                    if (lineItemContacts != null && !lineItemContacts.isEmpty()) {
                        for (Object contactObj : lineItemContacts) {
                            Map<String, Object> contact = (Map<String, Object>) contactObj;
                            String contactType = (String) contact.get('is_type');
                            String names = (String) contact.get('name');
                            String phone = (String) contact.get('phone');
                            String email = (String) contact.get('email_address');
                            
                            if ('billing'.equals(contactType)) {
                                carrier.Contact_Name_1__c = getFirstTwoWords(names);
                                carrier.Contact_Phone_1__c = phone;
                                carrier.Contact_Email_1__c = email;
                            } else if ('claims'.equals(contactType)) {
                                carrier.Contact_Name_2__c = getFirstTwoWords(names);
                                carrier.Contact_Phone_2__c = phone;
                                carrier.Contact_Email_2__c = email;
                            }
                        }
                    }
                }
                
                // Look for EIN in tax_identifiers
                List<Object> taxIdentifiers = (List<Object>) carrierData.get('tax_identifiers');
                if (taxIdentifiers != null && !taxIdentifiers.isEmpty()) {
                    for (Object taxIdObj : taxIdentifiers) {
                        Map<String, Object> taxId = (Map<String, Object>) taxIdObj;
                        if ('ein'.equals(taxId.get('is_type'))) {
                            carrier.FreightTM__Federal_ID__c = (String) taxId.get('value');
                            break;
                        }
                    }
                }
                
                System.debug('Parsed carrier_detail: Name=' + name + ', MC=' + mc + ', DOT=' + dot);
            } else {
                System.debug('No valid carrier_detail object found in response');
            }
            
            // Parse billing fields based on presence of factor or payment_method
            if (packetData.containsKey('factor') && packetData.get('factor') instanceof Map<String, Object> && (packetData.get('payment_method') == null || !(packetData.get('payment_method') instanceof Map<String, Object>))) {
                // Use factor
                Map<String, Object> factor = (Map<String, Object>) packetData.get('factor');
                
                // Set billing fields from factor
                String countryCodes = (String) factor.get('physical_address_country');
                carrier.FreightTM__Billing_Country__c = countryCodes != null ? getFullCountryName(countryCodes) : null;
                carrier.FreightTM__Billing_Address__c = formatAddress((String) factor.get('physical_address_street1'));
                carrier.FreightTM__Billing_City__c = (String) factor.get('physical_address_city');
                carrier.FreightTM__Billing_State_Province__c = (String) factor.get('physical_address_state');
                carrier.FreightTM__Billing_Zip_Code__c = (String) factor.get('physical_address_postal_code');
                carrier.Billing_Email__c = (String) factor.get('email_address');
                carrier.Routing__c = (String) factor.get('routing_number');
                carrier.Bank__c = (String) factor.get('bank_name');
                carrier.Billing_Name__c = (String) factor.get('name');
                carrier.Account__c = (String) factor.get('last_4_account_number');
                carrier.Payment_Method__c = 'ACH';
                
                System.debug('Using factor for billing fields: Billing_Address=' + carrier.FreightTM__Billing_Address__c + ', Billing_City=' + carrier.FreightTM__Billing_City__c + ', Billing_State=' + carrier.FreightTM__Billing_State_Province__c + ', Billing_Zip=' + carrier.FreightTM__Billing_Zip_Code__c + ', Billing_Email=' + carrier.Billing_Email__c + ', Routing=' + carrier.Routing__c + ', Bank=' + carrier.Bank__c + ', Payment_Method=' + carrier.Payment_Method__c + ', Billing_Name=' + carrier.Billing_Name__c);
            } else if ((packetData.get('factor') == null || !(packetData.get('factor') instanceof Map<String, Object>)) && packetData.containsKey('payment_method') && packetData.get('payment_method') instanceof Map<String, Object>) {
                // Use payment_method
                Map<String, Object> paymentMethod = (Map<String, Object>) packetData.get('payment_method');
                
                // Set billing fields from paymentMethod
                String countryCodes = (String) paymentMethod.get('country');
                carrier.FreightTM__Billing_Country__c = countryCodes != null ? getFullCountryName(countryCodes) : null;
                carrier.FreightTM__Billing_Address__c = formatAddress((String) paymentMethod.get('street1'));
                carrier.FreightTM__Billing_City__c = (String) paymentMethod.get('city');
                carrier.FreightTM__Billing_State_Province__c = (String) paymentMethod.get('state');
                carrier.FreightTM__Billing_Zip_Code__c = (String) paymentMethod.get('postal_code');
                carrier.Routing__c = (String) paymentMethod.get('routing_number');
                carrier.Bank__c = (String) paymentMethod.get('bank_name');
                
                if (carrier.Name != null) {
                    carrier.Billing_Name__c = carrier.Name;
                }
                
                carrier.Account__c = (String) paymentMethod.get('account_last_four');
                
                if (paymentMethod.containsKey('is_type')) {
                    carrier.Payment_Method__c = (String) paymentMethod.get('is_type');
                } else {
                    carrier.Payment_Method__c = null;
                }
                
                System.debug('Using payment_method for billing fields: Billing_Address=' + carrier.FreightTM__Billing_Address__c + ', Billing_City=' + carrier.FreightTM__Billing_City__c + ', Billing_State=' + carrier.FreightTM__Billing_State_Province__c + ', Billing_Zip=' + carrier.FreightTM__Billing_Zip_Code__c + ', Routing=' + carrier.Routing__c + ', Bank=' + carrier.Bank__c + ', Payment_Method=' + carrier.Payment_Method__c + ', Billing_Name=' + carrier.Billing_Name__c);
            } else {
                System.debug('Neither factor nor payment_method is suitable for billing fields');
            }
            
                          // Parse executed_contracts → only keep contracts for file processing (creator is now taken from invitation)
                if (packetData.containsKey('executed_contracts') && packetData.get('executed_contracts') instanceof List<Object>) {
                    List<Object> executedContractsList = (List<Object>) packetData.get('executed_contracts');
                    if (!executedContractsList.isEmpty()) {
                        executedContracts = executedContractsList;
                        System.debug('Parsed executed_contracts → ' + executedContracts.size() + ' contracts will be processed later');
                    } else {
                        System.debug('No executed contracts found in response');
                    }
                } else {
                    System.debug('No valid executed_contracts array found in response');
                }
                            
            result.put('carrier', carrier);
            result.put('contracts', executedContracts);
            
        } catch (Exception e) {
            System.debug('Error parsing onboarding packet response: ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
            throw e;
        }
        
        return result;
    }
    
 // Processes contracts after carriers have been upserted (have IDs).
private static void processContractsAfterUpsert(List<FreightTM__Carrier__c> carriers, Map<Integer, String> carrierDOTNumbers, Map<Integer, List<Object>> contractsToProcessLater) {
    System.debug('=== processContractsAfterUpsert: START ===');
    System.debug('carriers size=' + carriers.size());
    System.debug('carrierDOTNumbers size=' + carrierDOTNumbers.size());
    System.debug('contractsToProcessLater size=' + contractsToProcessLater.size());
    
    if (contractsToProcessLater.isEmpty()) {
        System.debug('No contracts to process');
        return;
    }
    
    // Create a map of DOT number to Carrier ID for lookup
    Map<String, Id> dotToCarrierId = new Map<String, Id>();
    for (FreightTM__Carrier__c carrier : carriers) {
        if (carrier.Id != null && carrier.FreightTM__USDOT_Number__c != null) {
            dotToCarrierId.put(carrier.FreightTM__USDOT_Number__c, carrier.Id);
            System.debug('Mapped DOT to ID: ' + carrier.FreightTM__USDOT_Number__c + ' -> ' + carrier.Id);
        } else {
            System.debug('Carrier missing ID or DOT: Id=' + carrier.Id + ', DOT=' + carrier.FreightTM__USDOT_Number__c);
        }
    }
    
    System.debug('dotToCarrierId map has ' + dotToCarrierId.size() + ' entries');
    
    // Prepare all contract file data for batch processing
    List<ContractFileData> batchData = new List<ContractFileData>();
    
    for (Integer carrierIdKey : contractsToProcessLater.keySet()) {
        List<Object> contracts = contractsToProcessLater.get(carrierIdKey);
        if (contracts == null || contracts.isEmpty()) {
            System.debug('No contracts for carrierIdKey: ' + carrierIdKey);
            continue;
        }
        
        System.debug('Processing contracts for carrierIdKey: ' + carrierIdKey + ', contract count=' + contracts.size());
        
        // Find the carrier's DOT number
        String dot = carrierDOTNumbers.get(carrierIdKey);
        if (dot == null) {
            System.debug('No DOT number found for carrierIdKey: ' + carrierIdKey);
            continue;
        }
        
        System.debug('Found DOT for carrierIdKey ' + carrierIdKey + ': ' + dot);
        
        // Find the carrier's Salesforce ID
        Id carrierSalesforceId = dotToCarrierId.get(dot);
        if (carrierSalesforceId == null) {
            System.debug('No Salesforce ID found for DOT: ' + dot + '. Available DOTs in map: ' + dotToCarrierId.keySet());
            continue;
        }
        
        System.debug('Found Salesforce ID for DOT ' + dot + ': ' + carrierSalesforceId);
        
        // Extract contract file data
        for (Object o : contracts) {
            Map<String, Object> contract = (Map<String, Object>) o;
            String type = (String) contract.get('is_type');
            
            if (type == 'w9' || type == 'broker_carrier_agreement') {
                Map<String, Object> file = (Map<String, Object>) contract.get('file');
                if (file != null && file.containsKey('url') && file.containsKey('filename')) {
                    ContractFileData fileData = new ContractFileData();
                    fileData.carrierId = carrierSalesforceId;
                    fileData.fileUrl = (String) file.get('url');
                    fileData.fileName = (String) file.get('filename');
                    fileData.contractType = type;
                    batchData.add(fileData);
                    System.debug('Added contract file: ' + fileData.fileName + ' for carrier ' + carrierSalesforceId);
                }
            }
        }
    }
    
    System.debug('Total contract files to process: ' + batchData.size());
    
    if (!batchData.isEmpty()) {
        // Use batch apex to process files one at a time
        ContractFileBatch batch = new ContractFileBatch(batchData);
        Database.executeBatch(batch, 1); // Batch size 1 = each file in separate transaction
    }
    
    System.debug('=== processContractsAfterUpsert: END ===');
}// Simple data structure for contract files
    public class ContractFileData {
        public Id carrierId { get; set; }
        public String fileUrl { get; set; }
        public String fileName { get; set; }
        public String contractType { get; set; }
    }
    
   

    
  public static void processSingleContractFile(String fileUrl, String fileName, Id carrierId, String contractType) {
    System.debug('=== processSingleContractFile: START ===');
    System.debug('fileName=' + fileName + ', carrierId=' + carrierId + ', contractType=' + contractType);
    
    // 1. FIRST: Download the file (CALL OUT - no DML yet)
    Blob fileBody = downloadFile(fileUrl);
    
    if (fileBody == null) {
        System.debug('File download failed for: ' + fileName);
        return;
    }
    
    System.debug('Successfully downloaded ' + fileName + ', size=' + fileBody.size());
    
    // 2. Delete existing documents of same type for this carrier
    deleteExistingContractDocuments(carrierId, contractType);
    
    // 3. THEN: Create ContentVersion (DML)
    ContentVersion cv = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName,
        VersionData = fileBody
    );
    
    try {
        insert cv;
        System.debug('Inserted ContentVersion: ' + cv.Id);
        
        // 4. FINALLY: Link to carrier (DML)
        linkSingleFileToCarrier(cv.Id, carrierId);
        
    } catch (Exception e) {
        System.debug('Error processing file: ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
    }
    
    System.debug('=== processSingleContractFile: END ===');
}


 // Deletes existing contract documents of a specific type for a carrier.
 public static void deleteExistingContractDocuments(Id carrierId, String contractType) {
    System.debug('deleteExistingContractDocuments: carrierId=' + carrierId + ', contractType=' + contractType);
    
    try {
        // Query for existing ContentDocumentLinks for this carrier
        List<ContentDocumentLink> existingLinks = [
            SELECT Id, ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :carrierId
        ];
        
        if (existingLinks.isEmpty()) {
            System.debug('No existing documents found for carrier ' + carrierId);
            return;
        }
        
        // Get ContentDocumentIds
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : existingLinks) {
            contentDocumentIds.add(link.ContentDocumentId);
        }
        
        // Query for ContentVersions to check their titles for contract type
        List<ContentVersion> existingVersions = [
            SELECT Id, Title, ContentDocumentId 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
        ];
        
        // Identify documents to delete based on filename patterns
        Set<Id> documentsToDelete = new Set<Id>();
        
        for (ContentVersion cv : existingVersions) {
            String title = cv.Title.toLowerCase();
            
            // Check if this is a contract document of the same type
            if (contractType == 'w9') {
                if (title.contains('w9') || title.contains('tax form') || title.contains('irs form')) {
                    documentsToDelete.add(cv.ContentDocumentId);
                    System.debug('Marking W9 document for deletion: ' + cv.Title);
                }
            } else if (contractType == 'broker_carrier_agreement') {
                if (title.contains('agreement') || title.contains('contract') || 
                    title.contains('broker') || title.contains('carrier')) {
                    documentsToDelete.add(cv.ContentDocumentId);
                    System.debug('Marking agreement document for deletion: ' + cv.Title);
                }
            }
        }
        
        if (!documentsToDelete.isEmpty()) {
            // Delete the ContentDocument records (this cascades to ContentDocumentLink and ContentVersion)
            List<ContentDocument> documentsToDeleteList = [
                SELECT Id FROM ContentDocument 
                WHERE Id IN :documentsToDelete
            ];
            
            System.debug('Deleting ' + documentsToDeleteList.size() + ' existing documents for carrier ' + carrierId);
            delete documentsToDeleteList;
        } else {
            System.debug('No existing ' + contractType + ' documents found to delete for carrier ' + carrierId);
        }
        
    } catch (Exception e) {
        System.debug('Error deleting existing documents: ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
    }
}
    

     // Links a single file to a carrier.
    public static void linkSingleFileToCarrier(Id contentVersionId, Id carrierId) {
        System.debug('linkSingleFileToCarrier: contentVersionId=' + contentVersionId + ', carrierId=' + carrierId);
        
        try {
            // Query for the ContentDocumentId
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            
            if (cv.ContentDocumentId != null) {
                ContentDocumentLink link = new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = carrierId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                );
                
                insert link;
                System.debug('Created ContentDocumentLink: ' + link.Id);
            } else {
                System.debug('ContentVersion has no ContentDocumentId');
            }
        } catch (Exception e) {
            System.debug('Error linking file: ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
        }
    }
    
    public static Blob downloadFile(String url) {
        System.debug('downloadFile: START url=' + (url != null ? url.substring(0, Math.min(100, url.length())) : 'null'));
        
        if (url == null || url == '') {
            System.debug('downloadFile: URL is null or empty');
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(120000); // 2 minute timeout for large files
        
        // For S3 presigned URLs, we need to follow redirects
        req.setHeader('Accept', '');
        
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('downloadFile: Response status=' + res.getStatusCode());
            
            if (res.getStatusCode() == 200) {
                Blob b = res.getBodyAsBlob();
                System.debug('downloadFile: SUCCESS - Downloaded ' + (b != null ? b.size() : 0) + ' bytes');
                return b;
            } else if (res.getStatusCode() >= 300 && res.getStatusCode() < 400) {
                // Handle redirect
                String redirectUrl = res.getHeader('Location');
                System.debug('downloadFile: Redirect ' + res.getStatusCode() + ' to ' + redirectUrl);
                return downloadFile(redirectUrl); // Recursive call
            } else {
                System.debug('downloadFile: FAILED - Status=' + res.getStatusCode());
                System.debug('downloadFile: Response headers=' + res.getHeaderKeys());
                return null;
            }
        } catch (Exception e) {
            System.debug('downloadFile: EXCEPTION - ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
            return null;
        }
    }
    

     // Makes a simple GET call to an API endpoint.
     // Used for fetching data without sending anything extra.

    public static HttpResponse makeApiCall(String endpoint, String method) {
        validateCalloutConfig(endpoint);
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        request.setHeader('Authorization', 'Bearer ' + HIGHWAY_API_KEY);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(60000); // Give it a minute to respond
        return new Http().send(request);
    }
    
    // Makes an API call with a body, like for POST requests.
    // Handy when we need to send data, like marking something as processed.
    public static HttpResponse makeApiCall(String endpoint, String method, String body) {
        validateCalloutConfig(endpoint);
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        request.setHeader('Authorization', 'Bearer ' + HIGHWAY_API_KEY);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(60000);
        request.setBody(body);
        return new Http().send(request);
    }
    public static HttpResponse makeApiCall(String endpoint, String method, String body,String contentType) {
        validateCalloutConfig(endpoint);
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        request.setHeader('Authorization', 'Bearer ' + HIGHWAY_API_KEY);
        request.setHeader('Content-Type', contentType);
        request.setHeader('Accept', 'application/json');
        request.setTimeout(60000);
        request.setBody(body);
        return new Http().send(request);
    }
    

    private static void validateCalloutConfig(String endpoint) {
        if (String.isBlank(endpoint)) {
            throw new CalloutException('Highway endpoint is not configured. Complete the Highway Custom Metadata records first.');
        }
        if (String.isBlank(HIGHWAY_API_KEY)) {
            throw new CalloutException('Highway API key is not configured. Complete the active Highway Custom Metadata record first.');
        }
    }

    // Logs API errors so we know what went wrong.
    // Makes debugging a lot easier!
    public static void handleApiError(String apiName, HttpResponse response) {
        String errorMsg = apiName + ' Error - Status: ' + response.getStatusCode() + ', Body: ' + response.getBody();
        System.debug(errorMsg);
    }
    
    // Loads the API settings from custom metadata types (StagingHighway__mdt or ProdHighway__mdt).
    // Uses ENVIRONMENT to determine which metadata type to query.
    public static void loadApiConfig() {
        try {
            System.debug('Loading API settings from custom metadata for environment: ' + ENVIRONMENT);
            
            // Determine which custom metadata type to query based on ENVIRONMENT
            String metadataType = ENVIRONMENT == 'prod' ? 'ProdHighway__mdt' : 'StagingHighway__mdt';
            
            // Query the custom metadata type (assuming one record per type)
            String query = 'SELECT api_key__c, endpoint_carrierAt__c, endpoint_MarkAlerts__c, ' +
                          'endpoint_carrierDl__c, endpoint_SyncCarrier__c, endpoint_NewOnboarding__c, ' +
                          'endpoint_MarkOnboarding__c,' +
                          'endpoint_GetOnboarding__c ' +
                          'FROM ' + metadataType + ' LIMIT 1';
            
            // Execute the dynamic SOQL query
            List<SObject> configRecords = Database.query(query);
            
            if (configRecords.isEmpty()) {
                System.debug('No configuration found for ' + metadataType);
                return;
            }
            
            // Extract configuration from the first record
            SObject config = configRecords[0];
            
            // Assign values to static variables
            HIGHWAY_API_KEY = (String) config.get('api_key__c');
            HIGHWAY_API_URL = (String) config.get('endpoint_carrierAt__c');
            CARRIER_API_URL = (String) config.get('endpoint_carrierDl__c');
            MARK_PROCESSED_URL = (String) config.get('endpoint_MarkAlerts__c');
            ONBOARDING_PACKETS_URL = (String) config.get('endpoint_NewOnboarding__c');
            MARK_ONBOARDING_PROCESSED_URL = (String) config.get('endpoint_MarkOnboarding__c');
            //RESET_PACKET_URL =(String) config.get('endpoint_RestOnboarding__c')??null;
            //RESET_ALERT_URL = (String) config.get('endpoint_ResetAlerts__c');
            SYNC_CARRIER_URL = (String) config.get('endpoint_SyncCarrier__c');
            ONBOARDING_PACKETS_URL_id = (String) config.get('endpoint_GetOnboarding__c');
            
            System.debug('API settings loaded successfully for ' + ENVIRONMENT);
        } catch (Exception e) {
            System.debug('Problem loading API config from custom metadata: ' + e.getMessage());
        }
    }
    

    // Pulls carrier IDs and object IDs out of an API response.
    // Works for both sync calls (just object IDs) and regular ones (carrier and object IDs).
    public static IdsWrapper extractCarrierIds(String responseBody, Boolean isSync) {
        List<Integer> carrierIds = new List<Integer>();
        List<Integer> objectIds = new List<Integer>();
        
        try {
            List<Object> responses = (List<Object>) JSON.deserializeUntyped(responseBody);
            
            for (Object responseObj : responses) {
                Map<String, Object> response = (Map<String, Object>) responseObj;
                
                if (response.containsKey('id')) {
                    Integer objectId = (Integer) response.get('id');
                    objectIds.add(objectId);
                }
                
                if (isSync) {
                    if (response.containsKey('id')) {
                        Integer carrierId = (Integer) response.get('id');
                        carrierIds.add(carrierId);
                    }
                } else {
                    if (response.containsKey('carrier_detail')) {
                        Map<String, Object> carrierDetail = (Map<String, Object>) response.get('carrier_detail');
                        if (carrierDetail != null && carrierDetail.containsKey('id')) {
                            Integer carrierId = (Integer) carrierDetail.get('id');
                            carrierIds.add(carrierId);
                        }
                    }
                }
            }
            
            System.debug('Extracted carrier IDs: ' + carrierIds);
            System.debug('Extracted object IDs: ' + objectIds);
            return new IdsWrapper(carrierIds, objectIds);
        } catch (Exception e) {
            System.debug('Error extracting IDs: ' + e.getMessage());
            return new IdsWrapper(new List<Integer>(), new List<Integer>());
        }
    }
    

    // Wrapper class to hold both carrier IDs and object IDs.
    public class IdsWrapper {
        public List<Integer> carrierIds { get; private set; }
        public List<Integer> objectIds { get; private set; }
        
        public IdsWrapper(List<Integer> carrierIds, List<Integer> objectIds) {
            this.carrierIds = carrierIds;
            this.objectIds = objectIds;
        }
    }
    

    // Marks alerts or onboarding packets as processed.
    // Switches between the two based on the isOnboarding flag.
    public static HttpResponse markAsProcessed(List<Integer> ids, Boolean isOnboarding) {
        String endpoint = isOnboarding ? MARK_ONBOARDING_PROCESSED_URL : MARK_PROCESSED_URL;
        String body;
        
        if (isOnboarding) {
            List<Map<String, Object>> packets = new List<Map<String, Object>>();
            for (Integer id : ids) {
                packets.add(new Map<String, Object>{'id' => id});
            }
            body = JSON.serialize(new Map<String, Object>{'onboarding_packets' => packets});
        } else {
            body = JSON.serialize(new Map<String, Object>{'ids' => ids});
        }
        
        return makeApiCall(endpoint, 'POST', body);
    }
    

    // Resets the processed status for alerts in sandbox.
    // Useful for testing and starting fresh.
    public static void resetProcessedAlerts() {
        HttpResponse response = makeApiCall(RESET_ALERT_URL, 'POST');
        if (response.getStatusCode() != 204) {
            handleApiError('Alerts reset', response);
            return;
        }
        System.debug(response);
    }
    

    // Resets the processed status for onboarding packets in sandbox.
    // Another handy tool for testing.
    public static void resetProcessedOnboardingPackets() {
        HttpResponse response = makeApiCall(RESET_PACKET_URL, 'POST');
        if (response.getStatusCode() != 204) {
            handleApiError('Packet reset', response);
            return;
        }
        System.debug(response);
    }
    
    public static String formatAddress(String street) {
        if (String.isBlank(street)) {
            return street; // Return as-is if empty
        }
        
        List<String> words = street.split(' '); // Split by spaces
        
        if (words.isEmpty()) {
            return street;
        }
        
        String firstWord = words[0];
        
        // Check if the first word is a number
        if (Pattern.matches('^[0-9]+$', firstWord)) {
            words.remove(0); // Remove the number
            words.add(firstWord); // Move it to the end
        }
        
        // Convert to Proper Case (capitalize first letter of each word)
        for (Integer i = 0; i < words.size(); i++) {
            words[i] = words[i].toLowerCase().capitalize();
        }
        
        return String.join(words, ' '); // Reconstruct the address
    }
    
    // Method to convert country code to full country name
    public static String getFullCountryName(String countryCode) {
        if (countryCode == null || countryCode.trim().length() != 2) {
            return null;
        }
        
        // Map of ISO 3166-1 alpha-2 codes to full country names
        Map<String, String> countryMap = new Map<String, String>{
            'AD' => 'Andorra',
            'AE' => 'United Arab Emirates',
            'AF' => 'Afghanistan',
            'AG' => 'Antigua and Barbuda',
            'AI' => 'Anguilla',
            'AL' => 'Albania',
            'AM' => 'Armenia',
            'AO' => 'Angola',
            'AQ' => 'Antarctica',
            'AR' => 'Argentina',
            'AS' => 'American Samoa',
            'AT' => 'Austria',
            'AU' => 'Australia',
            'AW' => 'Aruba',
            'AX' => '\u00c5land Islands',
            'AZ' => 'Azerbaijan',
            'BA' => 'Bosnia and Herzegovina',
            'BB' => 'Barbados',
            'BD' => 'Bangladesh',
            'BE' => 'Belgium',
            'BF' => 'Burkina Faso',
            'BG' => 'Bulgaria',
            'BH' => 'Bahrain',
            'BI' => 'Burundi',
            'BJ' => 'Benin',
            'BL' => 'Saint Barth\u00e9lemy',
            'BM' => 'Bermuda',
            'BN' => 'Brunei Darussalam',
            'BO' => 'Bolivia',
            'BQ' => 'Bonaire, Sint Eustatius and Saba',
            'BR' => 'Brazil',
            'BS' => 'Bahamas',
            'BT' => 'Bhutan',
            'BV' => 'Bouvet Island',
            'BW' => 'Botswana',
            'BY' => 'Belarus',
            'BZ' => 'Belize',
            'CA' => 'Canada',
            'CC' => 'Cocos (Keeling) Islands',
            'CD' => 'Congo, Democratic Republic of the',
            'CF' => 'Central African Republic',
            'CG' => 'Congo',
            'CH' => 'Switzerland',
            'CI' => 'C\u00f4te d\'Ivoire',
            'CK' => 'Cook Islands',
            'CL' => 'Chile',
            'CM' => 'Cameroon',
            'CN' => 'China',
            'CO' => 'Colombia',
            'CR' => 'Costa Rica',
            'CU' => 'Cuba',
            'CV' => 'Cabo Verde',
            'CW' => 'Cura\u00e7ao',
            'CX' => 'Christmas Island',
            'CY' => 'Cyprus',
            'CZ' => 'Czechia',
            'DE' => 'Germany',
            'DJ' => 'Djibouti',
            'DK' => 'Denmark',
            'DM' => 'Dominica',
            'DO' => 'Dominican Republic',
            'DZ' => 'Algeria',
            'EC' => 'Ecuador',
            'EE' => 'Estonia',
            'EG' => 'Egypt',
            'EH' => 'Western Sahara',
            'ER' => 'Eritrea',
            'ES' => 'Spain',
            'ET' => 'Ethiopia',
            'FI' => 'Finland',
            'FJ' => 'Fiji',
            'FK' => 'Falkland Islands (Malvinas)',
            'FM' => 'Micronesia, Federated States of',
            'FO' => 'Faroe Islands',
            'FR' => 'France',
            'GA' => 'Gabon',
            'GB' => 'United Kingdom',
            'GD' => 'Grenada',
            'GE' => 'Georgia',
            'GF' => 'French Guiana',
            'GG' => 'Guernsey',
            'GH' => 'Ghana',
            'GI' => 'Gibraltar',
            'GL' => 'Greenland',
            'GM' => 'Gambia',
            'GN' => 'Guinea',
            'GP' => 'Guadeloupe',
            'GQ' => 'Equatorial Guinea',
            'GR' => 'Greece',
            'GS' => 'South Georgia and the South Sandwich Islands',
            'GT' => 'Guatemala',
            'GU' => 'Guam',
            'GW' => 'Guinea-Bissau',
            'GY' => 'Guyana',
            'HK' => 'Hong Kong',
            'HM' => 'Heard Island and McDonald Islands',
            'HN' => 'Honduras',
            'HR' => 'Croatia',
            'HT' => 'Haiti',
            'HU' => 'Hungary',
            'ID' => 'Indonesia',
            'IE' => 'Ireland',
            'IL' => 'Israel',
            'IM' => 'Isle of Man',
            'IN' => 'India',
            'IO' => 'British Indian Ocean Territory',
            'IQ' => 'Iraq',
            'IR' => 'Iran, Islamic Republic of',
            'IS' => 'Iceland',
            'IT' => 'Italy',
            'JE' => 'Jersey',
            'JM' => 'Jamaica',
            'JO' => 'Jordan',
            'JP' => 'Japan',
            'KE' => 'Kenya',
            'KG' => 'Kyrgyzstan',
            'KH' => 'Cambodia',
            'KI' => 'Kiribati',
            'KM' => 'Comoros',
            'KN' => 'Saint Kitts and Nevis',
            'KP' => 'Korea, Democratic People\'s Republic of',
            'KR' => 'Korea, Republic of',
            'KW' => 'Kuwait',
            'KY' => 'Cayman Islands',
            'KZ' => 'Kazakhstan',
            'LA' => 'Lao People\'s Democratic Republic',
            'LB' => 'Lebanon',
            'LC' => 'Saint Lucia',
            'LI' => 'Liechtenstein',
            'LK' => 'Sri Lanka',
            'LR' => 'Liberia',
            'LS' => 'Lesotho',
            'LT' => 'Lithuania',
            'LU' => 'Luxembourg',
            'LV' => 'Latvia',
            'LY' => 'Libya',
            'MA' => 'Morocco',
            'MC' => 'Monaco',
            'MD' => 'Moldova, Republic of',
            'ME' => 'Montenegro',
            'MF' => 'Saint Martin (French part)',
            'MG' => 'Madagascar',
            'MH' => 'Marshall Islands',
            'MK' => 'North Macedonia',
            'ML' => 'Mali',
            'MM' => 'Myanmar',
            'MN' => 'Mongolia',
            'MO' => 'Macao',
            'MP' => 'Northern Mariana Islands',
            'MQ' => 'Martinique',
            'MR' => 'Mauritania',
            'MS' => 'Montserrat',
            'MT' => 'Malta',
            'MU' => 'Mauritius',
            'MV' => 'Maldives',
            'MW' => 'Malawi',
            'MX' => 'Mexico',
            'MY' => 'Malaysia',
            'MZ' => 'Mozambique',
            'NA' => 'Namibia',
            'NC' => 'New Caledonia',
            'NE' => 'Niger',
            'NF' => 'Norfolk Island',
            'NG' => 'Nigeria',
            'NI' => 'Nicaragua',
            'NL' => 'Netherlands',
            'NO' => 'Norway',
            'NP' => 'Nepal',
            'NR' => 'Nauru',
            'NU' => 'Niue',
            'NZ' => 'New Zealand',
            'OM' => 'Oman',
            'PA' => 'Panama',
            'PE' => 'Peru',
            'PF' => 'French Polynesia',
            'PG' => 'Papua New Guinea',
            'PH' => 'Philippines',
            'PK' => 'Pakistan',
            'PL' => 'Poland',
            'PM' => 'Saint Pierre and Miquelon',
            'PN' => 'Pitcairn',
            'PR' => 'Puerto Rico',
            'PS' => 'Palestine, State of',
            'PT' => 'Portugla',
            'PW' => 'Palau',
            'PY' => 'Paraguay',
            'QA' => 'Qatar',
            'RE' => 'R\u00e9union',
            'RO' => 'Romania',
            'RS' => 'Serbia',
            'RU' => 'Russian Federation',
            'RW' => 'Rwanda',
            'SA' => 'Saudi Arabia',
            'SB' => 'Solomon Islands',
            'SC' => 'Seychelles',
            'SD' => 'Sudan',
            'SE' => 'Sweden',
            'SG' => 'Singapore',
            'SH' => 'Saint Helena, Ascension and Tristan da Cunha',
            'SI' => 'Slovenia',
            'SJ' => 'Svalbard and Jan Mayen',
            'SK' => 'Slovakia',
            'SL' => 'Sierra Leone',
            'SM' => 'San Marino',
            'SN' => 'Senegal',
            'SO' => 'Somalia',
            'SR' => 'Suriname',
            'SS' => 'South Sudan',
            'ST' => 'Sao Tome and Principe',
            'SV' => 'El Salvador',
            'SX' => 'Sint Maarten (Dutch part)',
            'SY' => 'Syrian Arab Republic',
            'SZ' => 'Eswatini',
            'TC' => 'Turks and Caicos Islands',
            'TD' => 'Chad',
            'TF' => 'French Southern Territories',
            'TG' => 'Togo',
            'TH' => 'Thailand',
            'TJ' => 'Tajikistan',
            'TK' => 'Tokelau',
            'TL' => 'Timor-Leste',
            'TM' => 'Turkmenistan',
            'TN' => 'Tunisia',
            'TO' => 'Tonga',
            'TR' => 'T\u00fcrkiye',
            'TT' => 'Trinidad and Tobago',
            'TV' => 'Tuvalu',
            'TW' => 'Taiwan, Province of China',
            'TZ' => 'Tanzania, United Republic of',
            'UA' => 'Ukraine',
            'UG' => 'Uganda',
            'UM' => 'United States Minor Outlying Islands',
            'US' => 'United States',
            'UY' => 'Uruguay',
            'UZ' => 'Uzbekistan',
            'VA' => 'Holy See',
            'VC' => 'Saint Vincent and the Grenadines',
            'VE' => 'Venezuela',
            'VG' => 'Virgin Islands (British)',
            'VI' => 'Virgin Islands (U.S.)',
            'VN' => 'Viet Nam',
            'VU' => 'Vanuatu',
            'WF' => 'Wallis and Futuna',
            'WS' => 'Samoa',
            'YE' => 'Yemen',
            'YT' => 'Mayotte',
            'ZA' => 'South Africa',
            'ZM' => 'Zambia',
            'ZW' => 'Zimbabwe'
        };
        
        // Normalize input to uppercase for consistency
        String normalizedCode = countryCode.toUpperCase();
        
        // Return the full country name if found, null otherwise
        return countryMap.get(normalizedCode);
    }
    
    public static Date parseDateSafely(String dateStr, Integer minYear) {
        if (dateStr == null || dateStr.length() < 10) {
            System.debug('Invalid date string (null or too short): ' + dateStr);
            return null;
        }
        
        // Check if the string starts with a digit (e.g., "yyyy-MM-dd")
        if (!dateStr.substring(0, 1).isNumeric()) {
            System.debug('Date string does not start with a digit: ' + dateStr);
            return null;
        }
        
        // Extract the first 10 characters (assuming 'yyyy-MM-dd' format)
        String datePart = dateStr.substring(0, 10);
        
        try {
            // Attempt to parse as 'yyyy-MM-dd'
            Date parsedDate = Date.valueOf(datePart);
            
            // Check if the year is within the acceptable range
            if (parsedDate.year() >= minYear) {
                return parsedDate;
            } else {
                System.debug('Date year is too old: ' + parsedDate + ' for input: ' + dateStr);
                return null;
            }
        } catch (Exception ex) {
            System.debug('Invalid date format: ' + datePart + ' - Error: ' + ex.getMessage());
            return null;
        }
    }
    
    public static String getFirstTwoWords(String input) {
        if (input == null) {
            return null;
        }
        
        String[] words = input.trim().split('\\s+');
        if (words.size() >= 2) {
            return words[0] + ' ' + words[1];
        } else if (words.size() == 1) {
            return words[0];
        } else {
            return '';
        }
    }
}
