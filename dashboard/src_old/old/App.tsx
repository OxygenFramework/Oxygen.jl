
import { Component, useEffect, useState } from "react";
import Chart from 'react-apexcharts'

class SampleDonut extends Component {

  constructor(props: any) {
    super(props);

    this.state = {
      options: {},
      series: [44, 55, 41, 17, 15],
      labels: ['A', 'B', 'C', 'D', 'E']
    }
  }

  render() {

    return (
      <div className="donut">
        <Chart options={this.state.options} series={this.state.series} type="donut" width="380" />
      </div>
    );
  }
}

interface DonutProps {
    series: number[]
    labels: string[]
}

function Donut(props: DonutProps){

    const options = {
        series: props.series,
        labels: props.labels,   
    }
  
    return (
        <div className="donut">
            <Chart options={options} series={options.series} type="donut"/>
        </div>
    );
    
  }


export function App() {

    const [data, setData] = useState({})

    const duration = data.value?.history?.map(x => x.duration);
    const uris = data.value?.history?.map(x => x.uri);

    // for (const [k,v] of Object.entries(data?.endpoints)){
    //     console.log(k,v)
    // }

    const total_requests = Object.entries(data?.endpoints || {})?.reduce((acc, item) => {
            let [k,v] = item;
            acc.keys.push(k);
            acc.values.push(v.total_requests);
            return acc;

        }, {keys: [], values: []}
    )
    console.log(total_requests)

    useEffect(() => {
        async function load(){
            console.log("loading...")
            let freshData = await fetch("http://127.0.0.1:8080/docs/metrics/data").then(response => response.json());
            setData(freshData)
            console.log(freshData)
            console.log("loaded")
        }
        load();
        // setInterval(() => load(), 1000)
    }, []);

    // console.log(data.value)

    // console.log(duration.value)
    return <div>
        {/* <Donut/> */}
        {/* <SampleDonut/> */}
        <Donut series={total_requests.values} labels={total_requests.keys}/>    
    </div>;
}