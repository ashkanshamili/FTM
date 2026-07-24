public with sharing class AutoFillListController {
    
    private static final String BASE_URL = 'https://api-dev.freightgraph.ai';
    private static final String EMAIL_EXTRACTOR = '/api/EmailExtractor/process-email-with-files';

    @TestVisible
    private static String testAccessToken;
    
    public String emailContent { get; set; }
    public Blob uploadedFile1 { get; set; }
    public String uploadedFile1Name { get; set; }
    
    public Blob uploadedFile2 { get; set; }
    public String uploadedFile2Name { get; set; }
    
    private ApexPages.StandardSetController setController;
    
    public AutoFillListController(ApexPages.StandardSetController controller) {
        this.setController = controller;
    }
    
    public PageReference sendToApi() {
        List<FreightTM__Load__c> selectedLoads =
            (List<FreightTM__Load__c>) setController.getSelected();
        
        if (selectedLoads == null || selectedLoads.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Please select one Load record.'
            ));
            return null;
        }
        
        if (selectedLoads.size() > 1) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Please select only one Load record.'
            ));
            return null;
        }
        
        if (String.isBlank(emailContent)) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Description is required.'
            ));
            return null;
        }
        
        if (uploadedFile1 == null && uploadedFile2 == null) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Please upload at least one file.'
            ));
            return null;
        }
        
        FreightTM__Load__c loadRecord = [
            SELECT Id, Name
            FROM FreightTM__Load__c
            WHERE Id = :selectedLoads[0].Id
            LIMIT 1
        ];
        
        String token =
            Test.isRunningTest() &&
            !String.isBlank(testAccessToken)
            ? testAccessToken
            : FreightAuthApi.getStoredToken();

        if (String.isBlank(token)) {
            token = FreightAuthApi.authenticate();
        }
        
        String boundary = '----SalesforceBoundary' + String.valueOf(Crypto.getRandomLong()).replace('-', '');
        
        Map<String, String> fields = new Map<String, String>{
            'Username' => UserInfo.getUserName(),
                'EmailContent' => emailContent,
                'SenderEmail' => UserInfo.getUserEmail(),
                'Subject' => 'Load ' + loadRecord.Name,
                'TenantId' => UserInfo.getOrganizationId()
                };
                    
                    Blob requestBody = buildMultipartBody(boundary, fields);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + EMAIL_EXTRACTOR);
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setBodyAsBlob(requestBody);
        
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                'Email content and attachments were sent successfully.'
            ));
        } else {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'API call failed. Status: ' + res.getStatusCode() + ' Response: ' + res.getBody()
            ));
        }
        
        return null;
    }
    
    public PageReference cancel() {
        PageReference pageRef = new PageReference('/lightning/o/FreightTM__Load__c/list');
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    private Blob buildMultipartBody(String boundary, Map<String, String> fields) {
        String hexBody = '';
        
        for (String fieldName : fields.keySet()) {
            hexBody += EncodingUtil.convertToHex(Blob.valueOf(
                '--' + boundary + '\r\n' +
                'Content-Disposition: form-data; name="' + fieldName + '"\r\n\r\n' +
                fields.get(fieldName) + '\r\n'
            ));
        }
        
        if (uploadedFile1 != null) {
            hexBody += addFilePart(boundary, uploadedFile1Name, uploadedFile1);
        }
        
        if (uploadedFile2 != null) {
            hexBody += addFilePart(boundary, uploadedFile2Name, uploadedFile2);
        }
        
        hexBody += EncodingUtil.convertToHex(Blob.valueOf('--' + boundary + '--'));
        
        return EncodingUtil.convertFromHex(hexBody);
    }
    
    private String addFilePart(String boundary, String fileName, Blob fileBody) {
        String safeFileName = String.isBlank(fileName) ? 'attachment' : fileName;
        
        String hexPart = EncodingUtil.convertToHex(Blob.valueOf(
            '--' + boundary + '\r\n' +
            'Content-Disposition: form-data; name="Attachments"; filename="' + safeFileName + '"\r\n' +
            'Content-Type: application/octet-stream\r\n\r\n'
        ));
        
        hexPart += EncodingUtil.convertToHex(fileBody);
        hexPart += EncodingUtil.convertToHex(Blob.valueOf('\r\n'));
        
        return hexPart;
    }
}