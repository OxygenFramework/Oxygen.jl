import React from "react";
import ReactApexChart from "react-apexcharts";
// import { lineChartData, lineChartOptions } from "variables/charts";


export class LineChartCustom extends React.PureComponent {
  constructor(props) {
    super(props);
  }

  render() {
    return (
      <ReactApexChart
        options={{}}
        series={[]}
        type="area"
        width="100%"
        height="100%"
      />
    );
  }
}

