public with sharing class HighwayHttpClient {

    public static HttpResponse sendRequest(
        String path,
        String method,
        String body
    ) {

        HighwayConfig.load();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(HighwayConfig.BASE_URL + path);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + HighwayConfig.API_KEY);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);

        if (body != null) {
            req.setBody(body);
        }

        Http http = new Http();
        return http.send(req);
    }
}
