import { LightningElement, api } from 'lwc';

export default class DispatchMap extends LightningElement {
    @api selectedRecord;
    @api selectedType;
    @api selectedLoads = [];
    @api matchedStates = [];

    get hasMarker() {
        return this.mapMarkers.length > 0;
    }

    get markerCount() {
        return this.mapMarkers.length;
    }

    get mapEyebrow() {
        return 'Live Assignment Map';
    }

    get mapTitle() {
        if (this.selectedType === 'Truck') {
            return 'Truck Assignment Map';
        }

        if (this.selectedType === 'Driver') {
            return 'Driver Assignment Map';
        }

        if (this.selectedType === 'Carrier') {
            return 'Carrier Assignment Map';
        }

        return 'Assignment Map';
    }

    get mapMarkers() {
        const markers = [];

        const selectedEntityMarker = this.buildSelectedEntityMarker();

        if (selectedEntityMarker) {
            markers.push(selectedEntityMarker);
        }

        const selectedLoadMarkers = this.buildSelectedLoadMarkers();

        if (selectedLoadMarkers.length > 0) {
            markers.push(...selectedLoadMarkers);
        }

        return markers;
    }

    buildSelectedEntityMarker() {
        if (!this.selectedRecord) {
            return null;
        }

        const record = this.selectedRecord;

        const street =
            record.FreightTM__Address__c ||
            record.FreightTM__Billing_Address__c ||
            '';

        const city =
            record.FreightTM__City__c ||
            record.FreightTM__Billing_City__c ||
            '';

        const state =
            record.State_Province__c ||
            record.FreightTM__State__c ||
            record.FreightTM__State_Province__c ||
            record.FreightTM__Billing_State_Province__c ||
            record.FreightTM__License_Plate_State__c ||
            '';

        const postalCode =
            record.FreightTM__Zip_Code__c ||
            record.FreightTM__Billing_Zip_Code__c ||
            '';

        const country =
            record.FreightTM__Country__c ||
            record.FreightTM__Billing_Country__c ||
            'United States';

        if (!street && !city && !state && !postalCode) {
            return null;
        }

        return {
            location: {
                Street: street,
                City: city,
                State: state,
                PostalCode: postalCode,
                Country: country
            },
            title: `${this.selectedType}: ${record.Name}`,
            description: this.selectedEntityDescription,
            mapIcon: {
                path: 'M0-48c-9.94 0-18 8.06-18 18 0 13.5 18 30 18 30s18-16.5 18-30c0-9.94-8.06-18-18-18z',
                fillColor: '#DC2626',
                fillOpacity: 1,
                strokeColor: '#7F1D1D',
                strokeOpacity: 1,
                strokeWeight: 2,
                scale: 0.78,
                anchor: {
                    x: 0,
                    y: 0
                }
            }
        };
    }

    buildSelectedLoadMarkers() {
        if (!this.selectedLoads || this.selectedLoads.length === 0) {
            return [];
        }

        const markers = [];
        const selectedState = this.matchedStates?.length ? this.matchedStates[0] : '';

        this.selectedLoads.forEach((load) => {
            const marker = this.buildSingleMatchedLoadMarker(load, selectedState);

            if (marker) {
                markers.push(marker);
            }
        });

        return markers;
    }

    buildSingleMatchedLoadMarker(load, selectedState) {
        const pickupState = load.FreightTM__Pickup_State__c || '';
        const deliveryState = load.FreightTM__Delivery_State__c || '';

        if (selectedState && pickupState === selectedState) {
            return this.buildLoadMarker(load, 'Pickup');
        }

        if (selectedState && deliveryState === selectedState) {
            return this.buildLoadMarker(load, 'Delivery');
        }

        if (!selectedState) {
            return this.buildLoadMarker(load, 'Pickup');
        }

        return null;
    }

    buildLoadMarker(load, pointType) {
        const isPickup = pointType === 'Pickup';
        const markerLetter = isPickup ? 'P' : 'D';

        const street = isPickup
            ? load.FreightTM__Pickup_Address__c || ''
            : load.FreightTM__Delivery_Address__c || '';

        const city = isPickup
            ? load.FreightTM__Pickup_City__c || ''
            : load.FreightTM__Delivery_City__c || '';

        const state = isPickup
            ? load.FreightTM__Pickup_State__c || ''
            : load.FreightTM__Delivery_State__c || '';

        const postalCode = isPickup
            ? load.FreightTM__Pickup_Zip_Code__c || ''
            : load.FreightTM__Delivery_Zip_Code__c || '';

        const country = isPickup
            ? load.FreightTM__Pickup_Country__c || 'United States'
            : load.FreightTM__Delivery_Country__c || 'United States';

        if (!street && !city && !state && !postalCode) {
            return null;
        }

        return {
            location: {
                Street: street,
                City: city,
                State: state,
                PostalCode: postalCode,
                Country: country
            },
            title: `${markerLetter} - ${load.Name}`,
            description:
                `${pointType} Location` +
                `<br/>Load: ${load.Name}` +
                `<br/>Status: ${load.FreightTM__Status__c || ''}` +
                `<br/>${city}${city && state ? ', ' : ''}${state}`,
            mapIcon: {
                path: 'M0-48c-9.94 0-18 8.06-18 18 0 13.5 18 30 18 30s18-16.5 18-30c0-9.94-8.06-18-18-18z',
                fillColor: '#2563EB',
                fillOpacity: 1,
                strokeColor: '#1D4ED8',
                strokeOpacity: 1,
                strokeWeight: 1,
                scale: 0.52,
                anchor: {
                    x: 0,
                    y: 0
                }
            }
        };
    }

    get selectedEntityDescription() {
        if (!this.selectedRecord) {
            return '';
        }

        if (this.selectedType === 'Truck') {
            return `Truck Status: ${this.selectedRecord.FreightTM__Status__c || ''}`;
        }

        if (this.selectedType === 'Driver') {
            return `Driver Status: ${
                this.selectedRecord.Status__c ||
                this.selectedRecord.FreightTM__Status__c ||
                ''
            }`;
        }

        if (this.selectedType === 'Carrier') {
            return `Onboarding Status: ${
                this.selectedRecord.FreightTM__On_boarding_Status__c || ''
            }`;
        }

        return '';
    }
}



/*import { LightningElement, api } from 'lwc';

export default class DispatchMap extends LightningElement {
    @api selectedRecord;
    @api selectedType;
    @api selectedLoads = [];
    @api matchedStates = [];

    get hasMarker() {
        return this.mapMarkers.length > 0;
    }

    get mapTitle() {
        if (this.selectedType === 'Truck') {
            return 'Truck Location';
        }

        if (this.selectedType === 'Driver') {
            return 'Driver Location';
        }

        if (this.selectedType === 'Carrier') {
            return 'Carrier Location';
        }

        return 'Location Map';
    }

    get cardIcon() {
        if (this.selectedType === 'Truck') {
            return 'standard:shipment';
        }

        if (this.selectedType === 'Driver') {
            return 'standard:user';
        }

        if (this.selectedType === 'Carrier') {
            return 'standard:account';
        }

        return 'standard:location';
    }

    get mapMarkers() {
        const markers = [];

        const selectedEntityMarker = this.buildSelectedEntityMarker();

        if (selectedEntityMarker) {
            markers.push(selectedEntityMarker);
        }

        const selectedLoadMarkers = this.buildSelectedLoadMarkers();

        if (selectedLoadMarkers.length > 0) {
            markers.push(...selectedLoadMarkers);
        }

        return markers;
    }

    buildSelectedEntityMarker() {
        if (!this.selectedRecord) {
            return null;
        }

        const record = this.selectedRecord;

        const street =
            record.FreightTM__Address__c ||
            record.FreightTM__Billing_Address__c ||
            '';

        const city =
            record.FreightTM__City__c ||
            record.FreightTM__Billing_City__c ||
            '';

        const state =
            record.FreightTM__State__c ||
            record.FreightTM__License_Plate_State__c ||
            record.FreightTM__State_Province__c ||
            record.FreightTM__Billing_State_Province__c ||
            '';

        const postalCode =
            record.FreightTM__Zip_Code__c ||
            record.FreightTM__Billing_Zip_Code__c ||
            '';

        const country =
            record.FreightTM__Country__c ||
            record.FreightTM__Billing_Country__c ||
            'United States';

        if (!street && !city && !state && !postalCode) {
            return null;
        }

        return {
            location: {
                Street: street,
                City: city,
                State: state,
                PostalCode: postalCode,
                Country: country
            },
            title: `${this.selectedType}: ${record.Name}`,
            description: this.selectedEntityDescription,

            // This keeps the selected Carrier / Driver / Truck marker metadata as-is.
            icon: this.selectedEntityIcon
        };
    }

    buildSelectedLoadMarkers() {
        if (!this.selectedLoads || this.selectedLoads.length === 0) {
            return [];
        }

        const markers = [];
        const states = this.matchedStates || [];

        this.selectedLoads.forEach(load => {
            const pickupState = load.FreightTM__Pickup_State__c || '';
            const deliveryState = load.FreightTM__Delivery_State__c || '';

            const pickupMatches = states.includes(pickupState);
            const deliveryMatches = states.includes(deliveryState);

            if (pickupMatches) {
                const pickupMarker = this.buildLoadMarker(load, 'Pickup');

                if (pickupMarker) {
                    markers.push(pickupMarker);
                }
            }

            if (deliveryMatches) {
                const deliveryMarker = this.buildLoadMarker(load, 'Delivery');

                if (deliveryMarker) {
                    markers.push(deliveryMarker);
                }
            }
        });

        return markers;
    }

    buildLoadMarker(load, pointType) {
        const isPickup = pointType === 'Pickup';
        const markerLetter = isPickup ? 'P' : 'D';

        const street = isPickup
            ? load.FreightTM__Pickup_Address__c || ''
            : load.FreightTM__Delivery_Address__c || '';

        const city = isPickup
            ? load.FreightTM__Pickup_City__c || ''
            : load.FreightTM__Delivery_City__c || '';

        const state = isPickup
            ? load.FreightTM__Pickup_State__c || ''
            : load.FreightTM__Delivery_State__c || '';

        const postalCode = isPickup
            ? load.FreightTM__Pickup_Zip_Code__c || ''
            : load.FreightTM__Delivery_Zip_Code__c || '';

        const country = isPickup
            ? load.FreightTM__Pickup_Country__c || 'United States'
            : load.FreightTM__Delivery_Country__c || 'United States';

        if (!street && !city && !state && !postalCode) {
            return null;
        }

        return {
           location: {
              Street: street,
              City: city,
              State: state,
              PostalCode: postalCode,
              Country: country
           },
           title: `${markerLetter} - ${load.Name}`,
          description:
           `${pointType} Location` +
           `<br/>Load: ${load.Name}` +
           `<br/>Status: ${load.FreightTM__Status__c || ''}` +
           `<br/>${city}${city && state ? ', ' : ''}${state}`,

          // This changes the actual map marker.
          // Gray + smaller than the default red marker.
          mapIcon: {
             path: 'M0-48c-9.94 0-18 8.06-18 18 0 13.5 18 30 18 30s18-16.5 18-30c0-9.94-8.06-18-18-18z',
             fillColor: '#1E88E5',
             fillOpacity: 1,
             strokeColor: '#0D47A1',
             strokeOpacity: 1,
             strokeWeight: 1,
             scale: 0.55,
             anchor: {
              x: 0,
              y: 0
             }
          }
        };
    }

    get selectedEntityIcon() {
        if (this.selectedType === 'Truck') {
            return 'standard:shipment';
        }

        if (this.selectedType === 'Driver') {
            return 'standard:user';
        }

        if (this.selectedType === 'Carrier') {
            return 'standard:account';
        }

        return 'standard:location';
    }

    get selectedEntityDescription() {
        if (!this.selectedRecord) {
            return '';
        }

        if (this.selectedType === 'Truck') {
            return `Truck Status: ${this.selectedRecord.FreightTM__Status__c || ''}`;
        }

        if (this.selectedType === 'Driver') {
            return `Driver Status: ${
                this.selectedRecord.Status__c ||
                this.selectedRecord.FreightTM__Status__c ||
                ''
            }`;
        }

        if (this.selectedType === 'Carrier') {
            return `On-boarding Status: ${
                this.selectedRecord.FreightTM__On_boarding_Status__c || ''
            }`;
        }

        return '';
    }
}*/