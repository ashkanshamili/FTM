@RestResource(urlMapping='/autofill/pdf-preview/*')
global with sharing class AutoFillPdfPreviewRest {
    @HttpGet
    global static void previewPdf() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;

        if (request == null || response == null) {
            return;
        }

        String rawVersionId = request.requestURI == null
            ? null
            : request.requestURI.substringAfterLast('/');

        Id contentVersionId;
        try {
            if (String.isBlank(rawVersionId)) {
                throw new IllegalArgumentException('Missing ContentVersion Id.');
            }
            contentVersionId = (Id) rawVersionId;
        } catch (Exception invalidIdException) {
            writeError(response, 400, 'A valid ContentVersion Id is required.');
            return;
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, FileType, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH USER_MODE
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            writeError(response, 404, 'The requested file was not found or is not accessible.');
            return;
        }

        ContentVersion versionRecord = versions[0];
        Boolean isPdf =
            'PDF'.equalsIgnoreCase(versionRecord.FileType) ||
            'PDF'.equalsIgnoreCase(versionRecord.FileExtension);

        if (!isPdf) {
            writeError(response, 415, 'Inline preview is only available for PDF files.');
            return;
        }

        String fileName = buildFileName(
            versionRecord.Title,
            versionRecord.FileExtension
        );

        response.statusCode = 200;
        response.addHeader('Content-Type', 'application/pdf');
        response.addHeader(
            'Content-Disposition',
            'inline; filename="' + escapeHeaderValue(fileName) + '"'
        );
        response.addHeader('Cache-Control', 'private, max-age=300');
        response.addHeader('X-Content-Type-Options', 'nosniff');
        response.responseBody = versionRecord.VersionData;
    }

    private static void writeError(
        RestResponse response,
        Integer statusCode,
        String message
    ) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'text/plain; charset=UTF-8');
        response.responseBody = Blob.valueOf(message);
    }

    @TestVisible
    private static String buildFileName(String title, String extension) {
        String safeTitle = String.isBlank(title) ? 'document' : title.trim();
        String safeExtension = String.isBlank(extension)
            ? 'pdf'
            : extension.trim().toLowerCase();

        if (!safeTitle.toLowerCase().endsWith('.' + safeExtension)) {
            safeTitle += '.' + safeExtension;
        }

        return safeTitle;
    }

    @TestVisible
    private static String escapeHeaderValue(String value) {
        return String.valueOf(value)
            .replace('"', '')
            .replace('\r', '')
            .replace('\n', '');
    }
}