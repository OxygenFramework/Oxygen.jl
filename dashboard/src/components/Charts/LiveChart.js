import React, { useState, useEffect } from 'react';
import ReactApexChart from 'react-apexcharts';

export function RealtimeLineGraph() {
    const [series, setSeries] = useState([{ data: [{ x: new Date().getTime(), y: Math.random() * 100 }] }]);

    useEffect(() => {
      const interval = setInterval(() => {
        // setSeries([{ data: [...series[0].data.slice(Math.max(series[0].data.length - 29, 0)), { x: new Date().getTime(), y: Math.random() * 100 }] }]);

        setSeries([{ data: [...series[0].data, { x: new Date().getTime(), y: Math.random() * 100 }] }]);
      }, 1000);
      return () => clearInterval(interval);
    }, [series]);

  const options = {
    chart: { 
        type: 'line',
        animations: {
            enabled: true,
            easing: 'linear',
            dynamicAnimation: {
              speed: 1000
            }
          },
     },
    xaxis: { 
        type: 'datetime', 
        range: 60 * 1000 
    },
    stroke: { curve: 'straight' },
  };

  return <ReactApexChart options={options} series={series} type="line" height={350} />;
}
