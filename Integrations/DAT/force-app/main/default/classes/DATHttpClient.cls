public with sharing class DATHttpClient {
    public class Response {
        public Integer statusCode;
        public String body;
    }

    public static Response postLoad(Map<String, Object> payload) {
        return send('POST', '/posting/v2/loads', JSON.serialize(payload), false);
    }

    public static Response updateLoad(String datPostId, Map<String, Object> payload) {
        requirePostId(datPostId);
        return send(
            'PATCH',
            '/posting/v2/loads/' + EncodingUtil.urlEncode(datPostId, 'UTF-8'),
            JSON.serialize(payload),
            false
        );
    }

    public static Response deleteLoad(String datPostId) {
        requirePostId(datPostId);
        return send(
            'DELETE',
            '/posting/v2/loads/' + EncodingUtil.urlEncode(datPostId, 'UTF-8'),
            null,
            true
        );
    }

    private static Response send(String method, String path, String body, Boolean acceptNotFound) {
        DATIntegrationConfig.Settings settings = DATIntegrationConfig.requireEnabled();
        String orgToken = DATTokenService.getOrganizationToken();
        String userToken = DATTokenService.getUserToken(orgToken);

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint(path));
        request.setMethod(method);
        request.setTimeout(30000);
        request.setHeader('Accept', 'application/json');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('x-dat-partner-id', settings.partnerId);
        request.setHeader('Authorization', 'Bearer ' + userToken);
        if (body != null) {
            request.setBody(body);
        }

        HttpResponse httpResponse;
        try {
            httpResponse = new Http().send(request);
        } catch (System.CalloutException ex) {
            throw new DATIntegrationException('DAT callout failed. Check the Named Credential, network access, and vendor availability.');
        }

        Integer code = httpResponse.getStatusCode();
        if ((code >= 200 && code < 300) || (acceptNotFound && code == 404)) {
            Response result = new Response();
            result.statusCode = code;
            result.body = httpResponse.getBody();
            return result;
        }

        if (code == 401 || code == 403) {
            DATTokenService.clearTokens();
            throw new DATIntegrationException('DAT rejected the authentication or principal access (HTTP ' + code + ').');
        }
        if (code == 409) {
            throw new DATIntegrationException('DAT reported a conflict. Refresh the Load and verify whether it is already posted.');
        }
        if (code == 429) {
            throw new DATIntegrationException('DAT rate limit was reached. Try again after the vendor retry window.');
        }
        if (code >= 500) {
            throw new DATIntegrationException('DAT is temporarily unavailable (HTTP ' + code + ').');
        }
        throw new DATIntegrationException('DAT rejected the request with HTTP ' + code + '.');
    }

    private static String endpoint(String path) {
        if (Test.isRunningTest()) {
            return 'https://dat.test' + path;
        }
        return 'callout:DAT_Freight' + path;
    }

    private static void requirePostId(String datPostId) {
        if (String.isBlank(datPostId)) {
            throw new DATIntegrationException('DAT Post ID is missing.');
        }
    }
}
