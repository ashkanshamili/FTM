public without sharing class ContractFileBatch
    implements Database.Batchable<HighwayAPIService.ContractFileData>, Database.AllowsCallouts {

    private List<HighwayAPIService.ContractFileData> contractFiles;

    public ContractFileBatch(List<HighwayAPIService.ContractFileData> contractFiles) {
        this.contractFiles = contractFiles == null
            ? new List<HighwayAPIService.ContractFileData>()
            : contractFiles;
    }

    public Iterable<HighwayAPIService.ContractFileData> start(Database.BatchableContext context) {
        return contractFiles;
    }

    public void execute(
        Database.BatchableContext context,
        List<HighwayAPIService.ContractFileData> scope
    ) {
        for (HighwayAPIService.ContractFileData fileData : scope) {
            if (fileData == null || fileData.carrierId == null || String.isBlank(fileData.fileUrl)) {
                continue;
            }

            HighwayAPIService.processSingleContractFile(
                fileData.fileUrl,
                fileData.fileName,
                fileData.carrierId,
                fileData.contractType
            );
        }
    }

    public void finish(Database.BatchableContext context) {
        // No follow-up action is required.
    }
}
