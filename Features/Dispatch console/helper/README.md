FTM Dispatch Console Installation

This package assumes FTM is already installed in the Salesforce org.

1. Deploy the complete package

Copy every file into the matching Salesforce DX folders.

Deploy:


The package includes:
Dispatch Console Lightning App
Dispatch Console Lightning Page
Dispatch Console Lightning Page Tab
Dispatch Console User Permission Set
Apex classes and tests
Dispatch Console Lightning Web Components
Invoice and Rate Confirmation pages
Required Load, Employee, and Truck fields

2. Assign the Permission Set

The App does not become available to a user until the Permission Set is assigned.

Follow this exact path:
Go to Setup.
Open Users.
Open Users again.
Select the required User.
Find Permission Set Assignments.
Click Edit Assignments.
Select Dispatch Console User.
Click Add.
Click Save.
Quick path:

Setup → Users → Users → Select User → Permission Set Assignments → Edit Assignments → Dispatch Console User → Add → Save


3. Open Dispatch Console

After assigning the Permission Set:
Refresh Salesforce or sign out and sign back in.
Open the App Launcher.
Click View All.
Search for Dispatch Console.
Open the Dispatch Console application.
No separate FTM Lightning App is required.


4. Ping Driver requirement

Ping Driver requires the Driver Portal feature and these Load values:
Driver Portal Link
Driver Phone Number
Driver Phone Carrier
