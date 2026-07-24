@IsTest
private class AutoFillPdfPreviewRestTest {
    @IsTest
    static void returnsPdfInline() {
        ContentVersion versionRecord = new ContentVersion(
            Title = 'preview-test',
            PathOnClient = 'preview-test.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test')
        );
        insert versionRecord;

        RestRequest request = new RestRequest();
        request.httpMethod = 'GET';
        request.requestURI =
            '/services/apexrest/autofill/pdf-preview/' + versionRecord.Id;
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AutoFillPdfPreviewRest.previewPdf();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(
            Blob.valueOf('%PDF-1.4 test').toString(),
            RestContext.response.responseBody.toString()
        );
    }

    @IsTest
    static void rejectsInvalidId() {
        RestRequest request = new RestRequest();
        request.httpMethod = 'GET';
        request.requestURI =
            '/services/apexrest/autofill/pdf-preview/not-an-id';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AutoFillPdfPreviewRest.previewPdf();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsWhenRestContextIsMissing() {
        RestContext.request = null;
        RestContext.response = null;

        Test.startTest();
        AutoFillPdfPreviewRest.previewPdf();
        Test.stopTest();

        System.assertEquals(null, RestContext.response);
    }

    @IsTest
    static void rejectsMissingId() {
        RestRequest request = new RestRequest();
        request.httpMethod = 'GET';
        request.requestURI = '/services/apexrest/autofill/pdf-preview/';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        AutoFillPdfPreviewRest.previewPdf();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains(
                'valid ContentVersion Id'
            )
        );
    }

    @IsTest
    static void returnsNotFoundForValidMissingId() {
        RestRequest request = new RestRequest();
        request.httpMethod = 'GET';
        request.requestURI =
            '/services/apexrest/autofill/pdf-preview/068000000000000';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        AutoFillPdfPreviewRest.previewPdf();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsNonPdfFiles() {
        ContentVersion versionRecord = new ContentVersion(
            Title = 'plain-text-preview',
            PathOnClient = 'plain-text-preview.txt',
            VersionData = Blob.valueOf('plain text')
        );
        insert versionRecord;

        RestRequest request = new RestRequest();
        request.httpMethod = 'GET';
        request.requestURI =
            '/services/apexrest/autofill/pdf-preview/' + versionRecord.Id;
        RestContext.request = request;
        RestContext.response = new RestResponse();

        AutoFillPdfPreviewRest.previewPdf();

        System.assertEquals(415, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('PDF')
        );
    }

    @IsTest
    static void fileNameAndHeaderHelpersAreSafe() {
        System.assertEquals(
            'document.pdf',
            AutoFillPdfPreviewRest.buildFileName(null, null)
        );
        System.assertEquals(
            'invoice.pdf',
            AutoFillPdfPreviewRest.buildFileName(' invoice ', ' PDF ')
        );
        System.assertEquals(
            'invoice.pdf',
            AutoFillPdfPreviewRest.buildFileName('invoice.pdf', 'pdf')
        );
        System.assertEquals(
            'badname.pdf',
            AutoFillPdfPreviewRest.escapeHeaderValue('bad"name\r\n.pdf')
        );
    }
}