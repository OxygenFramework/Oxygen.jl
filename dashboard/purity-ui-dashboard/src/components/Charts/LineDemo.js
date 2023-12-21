import React from "react";
import ReactApexChart from "react-apexcharts";


const lineChartOptions = {
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
      type: "datetime",
      categories: [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ],
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
  };

export class LineChartDemo extends React.PureComponent {
    constructor(props) {
        super(props);
    }
    render() {

        const lineChartData = [
            {
              name: "Mobile apps",
              data: [50, 40, 300, 220, 500, 250, 400, 230, 500],
            },
            {
              name: "Websites",
              data: [30, 90, 40, 140, 290, 290, 340, 230, 400],
            },
          ];

          

        const state = {
            series: [{
                data: this.props.series
            }],
            options: lineChartOptions
            // options: {
            //     chart: {
            //         id: 'area-datetime',
            //         type: 'area',
            //         zoom: {
            //             autoScaleYaxis: true
            //         }
            //     },
            //     annotations: {
            //         yaxis: [{
            //             y: 30,
            //             borderColor: '#999',
            //             label: {
            //                 show: true,
            //                 text: 'Support',
            //                 style: {
            //                     color: "#fff",
            //                     background: '#00E396'
            //                 }
            //             }
            //         }],
            //         xaxis: [{
            //             borderColor: '#999',
            //             yAxisIndex: 0,
            //             label: {
            //                 show: true,
            //                 text: 'Rally',
            //                 style: {
            //                     color: "#fff",
            //                     background: '#775DD0'
            //                 }
            //             }
            //         }]
            //     },
            //     tooltip: {
            //         theme: "dark",
            //       },
              
            //       stroke: {
            //         curve: "smooth",
            //       },
            //     dataLabels: {
            //         enabled: false
            //     },
            //     markers: {
            //         size: 0,
            //         style: 'hollow',
            //     },
            //     xaxis: {
            //         type: 'datetime',
            //         // min: new Date('01 Mar 2012').getTime(),
            //         tickAmount: 6,
            //     },
            //     yaxis: {
            //         labels: {
            //           style: {
            //             colors: "#c8cfca",
            //             fontSize: "12px",
            //           },
            //         },
            //       },
            //       legend: {
            //         show: false,
            //       },
            //       grid: {
            //         strokeDashArray: 5,
            //       },
            //       fill: {
            //         type: "gradient",
            //         gradient: {
            //           shade: "light",
            //           type: "vertical",
            //           shadeIntensity: 0.5,
            //           gradientToColors: undefined, // optional, if not defined - uses the shades of same color in series
            //           inverseColors: true,
            //           opacityFrom: 0.8,
            //           opacityTo: 0,
            //           stops: [],
            //         },
            //         colors: ["#4FD1C5", "#2D3748"],
            //       },
            //       colors: ["#4FD1C5", "#2D3748"],
            // }
        };
        return (
            <div id="chart">
                <div id="chart-timeline">
                    <ReactApexChart 
                        options={lineChartOptions} 
                        series={lineChartData} 
                        type="area"
                        width="100%"
                        height="100%"
                    />
                </div>
            </div>
        );
    }
}