import React, { useState, useEffect } from "react";
import ReactApexChart from "react-apexcharts";
import moment from "moment";
import { Button, Box } from "@chakra-ui/react";

export const BrushChart = (props) => {

  const [chartData, setChartData] = useState([])
  const [range, setRange] = useState(null);

  const onBrushUpdate = (chartContext, xaxis) => {

    setRange({
      range: xaxis.max - xaxis.min,
      min: xaxis.min,
      max: xaxis.max
    })

    setChartOptions(prevOptions => ({
      ...prevOptions,
      xaxis: {
        ...prevOptions.xaxis,
        range: xaxis.max - xaxis.min,
        min: xaxis.min,
        max: xaxis.max
      }
    }));
  };

  // Function to update chart for real-time data
  const updateForRealTimeData = (newData) => {
    if (range) {
      setChartOptions(prevOptions => ({
        ...prevOptions,
        xaxis: {
          ...prevOptions.xaxis,
          range: range.range,
          min: range.min,
          max: range.max
        }
      }));
    }
    // Update chart data here as well
  };

  useEffect(() => {
    // Assuming props.data updates with new real-time data
    if (props.data.length) {
      updateForRealTimeData(props.data);
    }
  }, [props.data]);

  const [chartOptions, setChartOptions] = useState({
    chart: {
      id: 'chart2',
      type: 'line',
      toolbar: {
        autoSelected: 'pan',
        show: false
      }
    },
    stroke: {
      width: 3
    },
    dataLabels: {
      enabled: false
    },
   
    markers: {
      size: 0
    },
    xaxis: {
      type: 'datetime',
      range: 60_000,
      tickAmount: 3,
      labels: {
        formatter: function (value, timestamp) {
          // Format the label as a local time string
          return moment(value).format('hh:mm:ss A'); // Customize this format as needed
        },
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
    colors: ["#0BC5EA", "#2D3748"],
  });



  const [lineOptions, setLineOptions] = useState({
    chart: {
      id: 'chart1',
      height: 130,
      type: 'area',
      brush: {
        target: 'chart2',
        enabled: true
      },
      selection: {
        enabled: true
      },
      events: {
        brushScrolled: function (chartContext, { xaxis, yaxis }) {
          // console.log("burshed")
          onBrushUpdate(chartContext, xaxis)
        }
      }
    },
    xaxis: {
      type: 'datetime',
      tickAmount: 3,
      labels: {
        formatter: function (value, timestamp) {
          // Format the label as a local time string
          return moment(value).format('hh:mm:ss A'); // Customize this format as needed
        },
        style: {
          colors: "#c8cfca",
          fontSize: "12px",
        },
      },
    },
    yaxis: {
      tickAmount: 2,
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
    colors: ["#0BC5EA", "#2D3748"],
  })

  // resets the selection on both charts and goes back to the realtime view
  function clearSelect() {

    setRange(null); // Reset the custom range state

    setLineOptions(prevOptions => ({
      ...prevOptions,
      xaxis: {
        ...prevOptions,
        min: undefined,
        max: undefined
      }
    }));

    // Update only the main chart (top chart) to show the last 60 seconds
    setChartOptions(prevOptions => ({
      ...prevOptions,
      xaxis: {
        ...prevOptions.xaxis,
        min: undefined,
        max: undefined,
        range: 60_000 // 60 seconds
      }
    }));
  } 


  // keep the top chart data up to date
  useEffect(() => {
    setChartData(props.data);
  }, [props.data]);


  // Keep the bottom chart range up to date
  useEffect(() => {
    setLineOptions(prevOptions => ({
      ...prevOptions,
      xaxis: {
        ...prevOptions,
        range: props.range
      }
    }));

  }, [props.range]);

  return (
    <Box>
      <Box>
        <ReactApexChart
          options={chartOptions}
          series={[{ data: chartData }]}
          width="100%"
          height="70%"
        />
        <ReactApexChart
          options={lineOptions}
          series={[{ data: chartData }]}
          width="100%"
          height="30%"
        />
      </Box>
      <Box display="flex" justifyContent="flex-end">
        <Button size='sm' onClick={clearSelect}>reset</Button>
      </Box>
    </Box>
  );
};

