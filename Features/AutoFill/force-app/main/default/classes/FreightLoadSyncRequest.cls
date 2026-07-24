public class FreightLoadSyncRequest {
    public String method;
    public Id salesforceLoadId;
    public String freightGraphId;
    public String bodyJson;
    
    public FreightLoadSyncRequest() {
    }
    
    public FreightLoadSyncRequest(
        String method,
        Id salesforceLoadId,
        String freightGraphId,
        String bodyJson
    ) {
        this.method = method;
        this.salesforceLoadId = salesforceLoadId;
        this.freightGraphId = freightGraphId;
        this.bodyJson = bodyJson;
    }
}