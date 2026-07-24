FTM Load Board for Carrier Deployment

After deploying the complete LoadBoardForCarrier feature and all related dependencies, configure the Salesforce Site.

Site Setup

Go to:

Setup → Sites → Open the Site

Add this Visualforce page under Site Visualforce Pages:

LoadBoardForCarrierSiteHome

Open Public Access Settings and add this Apex class under Enabled Apex Class Access:

LoadBoardForCarrierController

Site Guest User Access

From:

Public Access Settings → Object Settings

give the Site Guest User the required object and field access:

Carrier: Read
Load: Read
Bid: Read and Create
Load Board Bid Request: Read and Create

Also enable access to all fields used by the Carrier Load Board, Bid, and Bid Request process.

Enable Carriers for the Load Board

Go to:

Setup → Object Manager → Carrier → Page Layouts

Add these fields to the Carrier page:

Load Board Active
Ready for Loads

For every Carrier record that should access the public Load Board, set both fields to True:

Load Board Active = True
Ready for Loads = True

If the Site Guest User cannot read the approved Carrier records because of record-level sharing, create a Guest User Sharing Rule under:

Setup → Sharing Settings → Carrier Sharing Rules

Use these criteria:

Load Board Active equals True
AND
Ready for Loads equals True

Share the matching Carrier records with the Load Board Site Guest User using Read Only access.