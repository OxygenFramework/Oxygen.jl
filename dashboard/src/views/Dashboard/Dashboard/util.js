import moment from "moment";

function unitToSeconds(unit, value) {
    const unitsInSeconds = {
        seconds: 1,
        minutes: 60,
        hours: 3600,
        days: 86400
    };
    return value * (unitsInSeconds[unit.toLowerCase()] || 1); // Default to 1 if the unit is unrecognized
}

function zeroOutSmallerFields(date, unit) {
    const newDate = new Date(date.getTime()); // Copy the original date

    if (unit === 'days') {
        newDate.setUTCHours(0);
    }
    if (unit === 'days' || unit === 'hours') {
        newDate.setUTCMinutes(0);
    }
    if (unit === 'days' || unit === 'hours' || unit === 'minutes') {
        newDate.setUTCSeconds(0);
    }
    newDate.setUTCMilliseconds(0); // Always zero out milliseconds

    return newDate;
}

export function fillMissingData(data, unit = 1000, fillToCurrent = true, sort = true) {

    // ensure the input dates are read in as utc
    let records = data.map(item => [moment.utc(item[0]), item[1]])

    // Ensure the input is sorted by timestamp
    if (sort) {
        records.sort((a, b) => a[0] - b[0]);
    }

    let filledRecords = [];
    let lastRecordTime = null;

    records.forEach((record, i) => {
        filledRecords.push(record);
        lastRecordTime = record[0];

        if (i < records.length - 1) {
            let nextTime = records[i + 1][0];
            while (lastRecordTime + unit < nextTime) {
                lastRecordTime += unit;
                filledRecords.push([lastRecordTime, 0]);
            }
        }
    });

    if (fillToCurrent && lastRecordTime !== null) {
        let startTime = new Date()

        while (lastRecordTime + unit < startTime) {
            lastRecordTime += unit;
            filledRecords.push([lastRecordTime, 0]);
        }
    }

    // make sure all data is localized when returned
    return filledRecords.map(t => [moment(t[0]).local().format(), t[1]]);
}

