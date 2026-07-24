FTM Driver Portal Deployment Package

This package was built from the supplied Salesforce source that was already deployed and verified visually in the source org. It preserves the working Driver Portal implementation, including the public driver portal, token handling, Load fields, event processing, email/SMS support, tests, and the Load record administration component shown in the supplied screenshot.

Load record component

The component shown in the screenshot is included in this package.
Lightning App Builder label: Driver Portal Admin Section
LWC bundle/API name: driverPortalAdminPanel
Runtime reference: c:driverPortalAdminPanel
Supported object: FreightTM__Load__c
Source path: force-app/main/default/lwc/driverPortalAdminPanel

In Lightning App Builder, do not search for Driver Portal FTM. The exact component label in this source is Driver Portal Admin Section.

The package does not deploy the complete Load Lightning Record Page by default. This prevents the deployment from overwriting an existing customer or FTM Load page. Add the component manually after the code deployment.

Required deployment order

1. Add the package to the FTM GitHub feature branch

Start from the FTM repository and the Driver Portal feature branch used by your team.
git checkout feature/driver-portal
Do not replace unrelated FTM metadata with the reference files in this package.

2. Confirm the FTM base dependencies

The target org/repository must already contain the FTM managed objects and fields used by the portal, including:

FreightTM__Load__c
FreightTM__Employee__c
FreightTM__Carrier__c
FreightTM__Site_Location__c

Standard FTM Load, Driver, pickup, delivery, status, and location fields referenced by the Apex controller

The optional pingDriverModal uses the existing FTM DispatchConsoleController. The default manifest/package.xml contains the standalone Driver Portal and Load administration component. Use manifest/package-with-dispatch-console.xml only when the FTM repository already contains DispatchConsoleController.

3. Configure the public Driver Portal URL

The supplied working source contains the source-org Site URL. Before deploying to another org, replace it with the target org's public Salesforce Site URL.

Update these locations:
Custom Label Driver_Portal_Base_URL in:force-app/main/default/labels/CustomLabels.labels-meta.xml
Expected format:

https://YOUR-SITE-DOMAIN.my.salesforce-sites.com/DriverPortal

SITE_BASE_URL in:force-app/main/default/classes/DriverLoadPortalTriggerHandler.cls
siteEndpoint in both Visualforce host pages:
force-app/main/default/pages/DriverPortal.page
force-app/main/default/pages/DriverLoadPortalHome.page
The Lightning Out endpoint must be the Site origin without the /DriverPortal page suffix:

https://YOUR-SITE-DOMAIN.my.salesforce-sites.com

When DriverPortalDispatchController is used, populate Portal Page URL on the Driver Portal Settings custom metadata record named Default with the complete /DriverPortal URL.

The current implementation generates links with a 14-day validity period.


4. Configure the Salesforce Site

The primary manifest intentionally excludes PortalSite.site-meta.xml because its Site Admin, guest record owner, domain, and Site name are org-specific. The retrieved source-org Site metadata is included only as a reference under:

reference/org-specific/PortalSite.site-meta.xml

In Setup:

Open Digital Experiences > All Sites or User Interface > Sites, depending on the org setup.

Create or open the public Visualforce Site used for Driver Portal.
Add DriverPortal as an enabled Visualforce page.
Add Apex access for DriverLoadPortalController and DriverLoadPortalTokenService to the Site guest user.
Confirm that Aura requests and guest Lightning Out access are enabled.
Grant the Site guest user the object and field access represented by Driver_Portal_Guest or Driver_Portal_Only_Guest.
Confirm that the public URL opens the Visualforce page without a Salesforce login prompt.

5. Assign internal permissions

Use Driver_Portal_Only_Admin when the narrower permission set matches the target org better.

Add the component to the Load record page

After the Driver Portal code is deployed:
In Salesforce Setup, open Object Manager.

Select Load (FreightTM__Load__c).

Open Lightning Record Pages.
Open the active Load record page and click Edit.
You can also open any Load record, click the gear icon, and select Edit Page.
In Lightning App Builder, search the custom component list for:
Driver Portal Admin Section
Drag Driver Portal Admin Section onto the Load record page.
Place it in the Details tab or another visible administration section.
Click Save.

Click Activate and assign the page to the required apps, profiles, and record types.
Open a Load that has a Driver assigned.

The section should display:

Generate or Refresh Driver Portal Link
Copy Link

Driver
Driver Portal Token Hash
Driver Portal Link
Driver Portal Active
Driver Portal Last Update
Driver Portal Expires At
Driver Portal Last Opened
Driver Portal Last Device





