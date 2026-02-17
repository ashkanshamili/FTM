public class DatPostLoadController {
    public List<DatPostLoad.LoadDetails> loadDetailsList { get; set; }
    
    public DatPostLoadController() {
        String orgToken = DatPostLoad.getOrganizationToken();
        if (orgToken != null) {
            String userToken = DatPostLoad.getUserToken(orgToken);
            if (userToken != null) {
                loadDetailsList = DatPostLoad.getLoadDetailsList(userToken);
            } else {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Failed to get User Token'));
            }
        } else {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Failed to get Organization Token'));
        }
    }
}