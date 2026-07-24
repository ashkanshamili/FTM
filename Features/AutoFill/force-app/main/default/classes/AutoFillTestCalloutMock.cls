@IsTest
public class AutoFillTestCalloutMock implements HttpCalloutMock {
    private final String extractionResponseBody;
    private final Integer extractionStatusCode;

    public AutoFillTestCalloutMock() {
        this('{"Success":true}', 200);
    }

    public AutoFillTestCalloutMock(String extractionResponseBody) {
        this(extractionResponseBody, 200);
    }

    public AutoFillTestCalloutMock(
        String extractionResponseBody,
        Integer extractionStatusCode
    ) {
        this.extractionResponseBody = String.isBlank(extractionResponseBody)
            ? '{}'
            : extractionResponseBody;
        this.extractionStatusCode = extractionStatusCode == null
            ? 200
            : extractionStatusCode;
    }

    public HttpResponse respond(HttpRequest request) {
        String endpoint = request == null
            ? ''
            : String.valueOf(request.getEndpoint());

        HttpResponse response = new HttpResponse();
        response.setHeader('Content-Type', 'application/json');

        if (endpoint.contains('/api/auth/login') ||
            endpoint.contains('/api/auth/refresh')) {
            response.setStatusCode(200);
            response.setBody(
                '{"token":"autofill-test-token","expiresIn":3600}'
            );
            return response;
        }

        if (endpoint.contains('/api/loads')) {
            response.setStatusCode(200);
            // Do not return an Id. This prevents the sync Queueable from
            // updating the Load again and keeps unrelated AutoFill tests small.
            response.setBody('{}');
            return response;
        }

        if (endpoint.contains('/api/EmailExtractor/process-email-with-files')) {
            response.setStatusCode(extractionStatusCode);
            response.setBody(extractionResponseBody);
            return response;
        }

        response.setStatusCode(200);
        response.setBody('{}');
        return response;
    }
}