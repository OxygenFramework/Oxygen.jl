// Chakra imports
import {
  Flex,
  Grid,
  Image,
  SimpleGrid,
  useColorModeValue,
} from "@chakra-ui/react";
// assets
import peopleImage from "assets/img/people-image.png";
import logoChakra from "assets/svg/logo-white.svg";
import BarChart from "components/Charts/BarChart";
import LineChart from "components/Charts/LineChart";
import {DonutChart} from "components/Charts/DonutChart";
import {TimeSeriesChart} from "components/Charts/TimeSeriesChart";
import {LineChartCustom} from "components/Charts/LineChartCustom";

// Custom icons
import {
  CartIcon,
  DocumentIcon,
  GlobeIcon,
  WalletIcon,
} from "components/Icons/Icons.js";
import React from "react";
import { dashboardTableData, timelineData } from "variables/general";
import ActiveUsers from "./components/ActiveUsers";
import BuiltByDevelopers from "./components/BuiltByDevelopers";
import MiniStatistics from "./components/MiniStatistics";
import OrdersOverview from "./components/OrdersOverview";
import Projects from "./components/Projects";
import SalesOverview from "./components/SalesOverview";
import WorkWithTheRockets from "./components/WorkWithTheRockets";
import { getMetrics, globalState } from "../../../state/index.ts";

// "95th_percentile_latency": 0.5103640556335449,
// "avg_latency": 0.10452442169189453,
// "max_latency": 0.5103640556335449,
// "total_requests": 5,
// "min_latency": 0.000011920928955078125,
// "error_rate": 0.2

import { useHookstate, State } from '@hookstate/core';

export default function Dashboard() {
  const iconBoxInside = useColorModeValue("white", "white");
  // const {server, history, endpoints} = getMetrics();

  const state = useHookstate(globalState);

  const server = state.metrics.server.get();

  const bins = state.metrics.bins.get() || [];

  const total_requests = Object.entries(state.metrics.endpoints.get() || {})?.reduce((acc, item) => {
        let [k,v] = item;
        acc.keys.push(k);
        acc.values.push(v.total_requests);
        return acc;

    }, {keys: [], values: []}
  )

  const hardcoded_data = {
    "bins": [
      {
          "count": 4,
          "timestamp": "2023-12-21T03:16:00.0"
      },
      {
          "count": 10,
          "timestamp": "2023-12-21T03:15:00.0"
      },
      {
          "count": 19,
          "timestamp": "2023-12-21T03:14:00.0"
      },
      {
          "count": 60,
          "timestamp": "2023-12-21T03:13:00.0"
      },
      {
          "count": 60,
          "timestamp": "2023-12-21T03:12:00.0"
      },
      {
          "count": 61,
          "timestamp": "2023-12-21T03:11:00.0"
      },
      {
          "count": 59,
          "timestamp": "2023-12-21T03:10:00.0"
      },
      {
          "count": 26,
          "timestamp": "2023-12-21T03:09:00.0"
      },
      {
          "count": 27,
          "timestamp": "2023-12-21T03:08:00.0"
      },
      {
          "count": 38,
          "timestamp": "2023-12-21T03:07:00.0"
      },
      {
          "count": 18,
          "timestamp": "2023-12-21T03:06:00.0"
      },
      {
          "count": 13,
          "timestamp": "2023-12-21T03:05:00.0"
      }
  ]
  }



let data = {
  series: [{
    data: bins.map(bin => bin.count)
  }]

  }


  let chartops = {
    xaxis: {
      type: "datetime",
      categories: [bins.map(bin => bin.timestamp)],
      labels: {
        style: {
          colors: "#c8cfca",
          fontSize: "12px",
        },
      },
    }
  }

  console.log(chartops)
  return (
    <Flex flexDirection='column' pt={{ base: "120px", md: "75px" }}>
      <SimpleGrid columns={{ sm: 1, md: 2, xl: 3 }} spacing='24px'>
        <MiniStatistics
          title={"Total Requests"}
          amount={server.total_requests}
          percentage={undefined}
          icon={<WalletIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
        <MiniStatistics
          title={"Error Rate"}
          amount={(server.error_rate * 100).toFixed(2) + "%"}
          percentage={undefined}
          icon={<GlobeIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
        <MiniStatistics
          title={"Avg Latency"}
          amount={(server.avg_latency * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<DocumentIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
        <MiniStatistics
          title={"95th Percentile Latency"}
          amount={(server.percentile_latency_95th * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<CartIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
        <MiniStatistics
          title={"Min Latency"}
          amount={(server.min_latency  * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<DocumentIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
        <MiniStatistics
          title={"Max Latency"}
          amount={(server.max_latency  * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<DocumentIcon h={"24px"} w={"24px"} color={iconBoxInside} />}
        />
      </SimpleGrid>
      <Grid
        templateColumns={{ md: "1fr", lg: "1.8fr 1.2fr" }}
        templateRows={{ md: "1fr auto", lg: "1fr" }}
        my='26px'
        gap='24px'>
        {/* <BuiltByDevelopers
          title={"Built by Developers"}
          name={"Oxygen Metrics Dashboard"}
          description={
            "From colors, cards, typography to complex elements, you will find the full documentation."
          }
          image={
            <Image
              src={logoChakra}
              alt='chakra image'
              minWidth={{ md: "300px", lg: "auto" }}
            />
          }
        />
        <WorkWithTheRockets
          backgroundImage={peopleImage}
          title={"Work with the rockets"}
          description={
            "Wealth creation is a revolutionary recent positive-sum game. It is all about who takes the opportunity first."
          }
        /> */}
      </Grid>
      <Grid
        templateColumns={{ sm: "1fr", lg: "1.3fr 1.7fr" }}
        templateRows={{ sm: "repeat(2, 1fr)", lg: "1fr" }}
        gap='24px'
        mb={{ lg: "26px" }}>
        <ActiveUsers
          title={"Active Users"}
          percentage={23}
          chart={<BarChart />}
        />
        <SalesOverview
          title={"Sales Overview"}
          percentage={5}
          chart={<LineChart />}
        />

        <SalesOverview
          title={"Requests Distribution"}
          percentage={undefined}
          chart={<DonutChart series={total_requests.values} options={{labels: total_requests.keys}}/>}
        />
        <SalesOverview
            title={"Time Series"}
            percentage={undefined}
            chart={<LineChartCustom series={data} options={chartops}/>}
          />
        
      </Grid>

    </Flex>
  );
}
