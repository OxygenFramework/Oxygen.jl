import React, { Component, PureComponent } from "react";
import Card from "../Card/Card";
import Chart from "react-apexcharts";

export class DonutChart extends PureComponent {

  constructor(props) {
    super(props);
  }

  render() {
    return (
      <Chart
        options={this.props.options}
        series={this.props.series}
        type="donut"
        width="100%"
        height="100%"
      />
    );
  }
}

