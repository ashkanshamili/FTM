@IsTest
public class CustomerPortalTestDataFactory {
    /**
     * FreightTM__Load__c DML fires LoadTrigger, which enqueues
     * FreightLoadSyncQueueable. The queueable performs FreightGraph HTTP
     * callouts, so tests that create or update loads must register this mock.
     */
    private class FreightGraphCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request == null ? null : request.getEndpoint();
            if (endpoint != null &&
                (endpoint.contains('/api/auth/login') || endpoint.contains('/api/auth/refresh'))) {
                response.setBody('{"access_token":"customer-portal-test-token","expiresIn":3600}');
                return response;
            }

            // Do not return an Id for load synchronization. Returning an Id
            // updates Freight_Id__c and can enqueue another synchronization job.
            response.setBody('{}');
            return response;
        }
    }

    public static void registerFreightGraphCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new FreightGraphCalloutMock());
    }

    public static Account createAccount(String suffix) {
        Account accountRec = new Account(Name = 'Customer Portal Test ' + suffix);
        insert accountRec;
        return accountRec;
    }

    public static Contact createContact(Id accountId, String suffix) {
        Contact contactRec = new Contact(
            AccountId = accountId,
            FirstName = 'Portal',
            LastName = 'Contact ' + suffix,
            Email = 'portal.' + suffix.toLowerCase().replaceAll('[^a-z0-9]', '') + '@example.com'
        );
        insert contactRec;
        return contactRec;
    }

    public static FreightTM__Load__c createLoad(
        Id accountId,
        String statusValue,
        Decimal customerRate,
        String suffix
    ) {
        FreightTM__Load__c loadRec = new FreightTM__Load__c(
            FreightTM__Customer__c = accountId,
            FreightTM__Status__c = statusValue,
            FreightTM__Pickup_City__c = 'Houston',
            FreightTM__Pickup_State__c = 'TX',
            FreightTM__Pickup_Address__c = '100 Pickup Street',
            FreightTM__Pickup_Zip_Code__c = '77001',
            FreightTM__Pickup_Date__c = Date.today(),
            FreightTM__Delivery_City__c = 'Phoenix',
            FreightTM__Delivery_State__c = 'AZ',
            FreightTM__Delivery_Address__c = '200 Delivery Avenue',
            FreightTM__Delivery_Zip_Code__c = '85001',
            FreightTM__Delivery_Date__c = Date.today().addDays(1),
            FreightTM__Rate__c = customerRate,
            FreightTM__Weight__c = 42000,
            FreightTM__Number_of_Pallets__c = 20,
            FreightTM__Confirmation_Number__c = 'CP-' + suffix
        );
        insert loadRec;
        return loadRec;
    }

    public static String createSession(
        Id accountId,
        Id contactId,
        Boolean active,
        Datetime expiresAt,
        String suffix
    ) {
        String rawToken = 'customer-portal-token-' + suffix;
        insert new Customer_Portal_Session__c(
            Account__c = accountId,
            Contact__c = contactId,
            Token_Hash__c = CustomerPortalTokenService.hashToken(rawToken),
            Active__c = active,
            Expires_At__c = expiresAt,
            Portal_Link__c = 'https://example.com/CustomerPortal?t=' + suffix
        );
        return rawToken;
    }

    public static ContentVersion createFile(Id linkedEntityId, String title, String bodyText) {
        ContentVersion versionRec = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(bodyText),
            FirstPublishLocationId = linkedEntityId
        );
        insert versionRec;
        return [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :versionRec.Id
        ];
    }

    public static String longText(Integer lengthValue) {
        String value = '';
        while (value.length() < lengthValue) {
            value += '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        }
        return value.substring(0, lengthValue);
    }
}