@isTest
global class MockMacropointOrderRestAPI implements HttpCalloutMock {
    // Implement this interface method
    global HTTPResponse respond(HTTPRequest req) {
        // Optionally, only send a mock response for a specific endpoint
        // and method.
        System.assertEquals('https://macropoint-lite.com/api/1.0/orders/createorder', req.getEndpoint());
        System.assertEquals('POST', req.getMethod());
        
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/xml');
        //res.setBody('{"example":"test"}');
        res.setStatusCode(200);
        return res;
    }
}