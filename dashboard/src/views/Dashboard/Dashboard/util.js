export function fillMissingData(data, unit = 1000, fillToCurrent = true, sort = true) {

    let records = data;

    // Ensure the input is sorted by timestamp
    if (sort) {
        records.sort((a, b) => a[0] - b[0]);
    }

    let filledRecords = [];
    let lastRecordTime = null;

    for(let i=0; i < records.length; i++){
        let record = records[i];
        filledRecords.push(record);
        lastRecordTime = record[0].getTime();

        if (i < records.length - 1) {
            let nextTime = records[i + 1][0].getTime();
            while (lastRecordTime + unit < nextTime) {
                lastRecordTime += unit;
                filledRecords.push([lastRecordTime, 0]);
            }
        }
    }

    if (fillToCurrent && lastRecordTime !== null) {
        let startTime = new Date()

        while (lastRecordTime + unit < startTime) {
            lastRecordTime += unit;
            filledRecords.push([lastRecordTime, 0]);
        }
    }

    return filledRecords
}

