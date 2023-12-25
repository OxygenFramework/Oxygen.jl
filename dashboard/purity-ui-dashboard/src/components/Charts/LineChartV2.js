import React, { useState, useEffect } from "react";
import ReactApexChart from "react-apexcharts";

export const LineChartV2 = (props) => {

  const [chartOptions, setChartOptions] = useState({
    options: {
      stacked: false,
      chart: {
        toolbar: {
          show: false,
        },
      },
      tooltip: {
        theme: "dark",
      },
      dataLabels: {
        enabled: false,
      },
      stroke: {
        curve: "smooth",
      },
      xaxis: {
        type: 'datetime',
        labels: {
          style: {
            colors: "#c8cfca",
            fontSize: "12px",
          },
        },
      },
      yaxis: {
        labels: {
          style: {
            colors: "#c8cfca",
            fontSize: "12px",
          },
          formatter: function (value) {
            // Check if the value has more than three decimal places
            if (value % 1 !== 0) {
              return parseFloat(value).toFixed(3);
            }
            // If it doesn't have more than three decimal places, leave it as is
            return value;
          },
        },
      },
      legend: {
        show: false,
      },
      grid: {
        strokeDashArray: 5,
      },
      fill: {
        type: "gradient",
        gradient: {
          shade: "light",
          type: "vertical",
          shadeIntensity: 0.5,
          gradientToColors: undefined, // optional, if not defined - uses the shades of same color in series
          inverseColors: true,
          opacityFrom: 0.8,
          opacityTo: 0,
          stops: [],
        },
        colors: ["#4FD1C5", "#2D3748"],
      },
      colors: ["#4FD1C5", "#2D3748"],
    }
  });

  const [chartData, setChartData] = useState({
    series: [
      {
        name: "Total Requests",
        data: [],
      },
    ],
  })

  useEffect(() => {
    setChartData({
      series: [
        {
          name: "Total Requests",
          data: props.data,
        }
      ],
    });
  }, [props.data]);

  return (
    <ReactApexChart
      options={chartOptions.options}
      series={chartData.series}
      type="area"
      width="100%"
      height="100%"
    />
  );
};

