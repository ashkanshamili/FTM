FTM Customer Portal deployment

This package assumes that FTM is already installed in the target Salesforce org.

1. Add the code

Copy every file from the GitHub folder:

feature/customer-portal

into the matching folders of the Salesforce project opened in VS Code.

Deploy only the Customer Portal files. Do not deploy the full org source.

2. Configure the Salesforce Site

Go to:

Setup → Sites → Customer Portal

Confirm:

Active is checked.

Active Site Home Page is CustomerPortal.

Lightning Features for Guest Users is enabled.

Redirect to custom domain is disabled unless a real primary custom URL is configured.

Under Site Visualforce Pages, make sure these pages are enabled:

CustomerPortal

Invoice

BOL from the FTM managed package

CustomerPortalSiteTemplate

CustomerPortalSiteError

CustomerPortalSiteMaintenance

The Customer Portal now uses the existing FTM document pages:

/apex/BOL?id=<LoadId>
/apex/Invoice?id=<LoadId>

It no longer uses CustomerPortalPdf.

3. Add fields to the Account layout

Go to:

Setup → Object Manager → Account → Page Layouts → Account Layout

Add:

Customer Portal Username

Customer Portal Password

Customer Portal Active

Customer Portal Email

Save the layout.

4. Configure the customer Account

Open the customer Account and enter the portal username and password. Enable Customer Portal Active and save.

5. Test

Open the public Salesforce Site URL in an Incognito window, log in as the customer, and test:

BOL

Invoice

Shipments

Documents