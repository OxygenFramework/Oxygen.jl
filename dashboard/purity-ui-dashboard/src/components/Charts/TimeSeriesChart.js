import React, { Component, PureComponent } from "react";
import Card from "../Card/Card";
import Chart from "react-apexcharts";

export class TimeSeriesChart extends PureComponent {

  constructor(props) {
    super(props);
  }

  render() {

    const options = {

        series: [{
            data: [[1324508400000, 34], [1324594800000, 54], [1326236400000, 43]]
        }],
        chart: {
            type: 'area',
          },
          xaxis: {
            type: 'datetime',
            min: new Date('01 Mar 2012').getTime(),
            tickAmount: 6,
          },
    }

    return (
      <Chart
        options={options}
        series={options.series}
        type="donut"
        width="100%"
        height="100%"
      />
    );
  }
}
