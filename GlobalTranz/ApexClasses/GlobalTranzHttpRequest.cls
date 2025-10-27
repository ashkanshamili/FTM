public with sharing class GlobalTranzHttpRequest {
    private static final String BASE_URL = 'https://dev.gtzintegrate.com/';
    //private static final String BASE_URL = 'https://api.gtzintegrate.com/';  ===> prod
    private static final String SUBSCRIPTION_KEY = 'Your-Key';
    private static final String USERNAME = 'Your-Username';
    private static final String PASSWORD = 'Your-Password';
    
    public static HttpResponse send(String body, String endpoint, String method){
        HttpRequest r = new HttpRequest();
        String endpointURL = BASE_URL + endpoint + '?subscription-key=' + EncodingUtil.urlEncode(SUBSCRIPTION_KEY, 'UTF-8');
        r.setEndpoint(endpointURL);
        r.setMethod(method);
        r.setHeader('Content-Type', 'application/json');
        String basic = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(USERNAME + ':' + PASSWORD));
        r.setHeader('Authorization', basic);
        r.setTimeout(120000);
        r.setBody(body);
        
        Http http = new Http();
        HTTPResponse res = http.send(r);
        
        
        return res;
    }
}