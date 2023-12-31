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
import {LineChartDemo} from "components/Charts/LineDemo";
import {LineChartV2} from "components/Charts/LineChartV2"
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

import { useHookstate, State } from '@hookstate/core';

export default function Dashboard() {
  const iconBoxInside = useColorModeValue("white", "white");
  const state = useHookstate(globalState);

  const server = state.metrics.server.get();
  const {
    avg_latency_per_minute,
    requests_per_minute,
    avg_latency_per_second,
    requests_per_second
  } = state.metrics.get();

  const total_requests = Object.entries(state.metrics.endpoints.get() || {})?.reduce((acc, item) => {
      let [k,v] = item;
      acc.keys.push(k);
      acc.values.push(v.total_requests);
      return acc;
    }, {keys: [], values: []}
  )

  const all_errors = Object.entries(state.metrics.errors.get() || {})?.reduce((acc, item) => {
      let [k,v] = item;
      acc.keys.push(k);
      acc.values.push(v);
      return acc;
    }, {keys: [], values: []}
  )

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

      </Grid>
      <Grid
        templateColumns={{ sm: "1fr", lg: "1.5fr 1.5fr" }}
        templateRows={{ sm: "repeat(2, 1fr)", lg: "1fr" }}
        gap='24px'
        mb={{ lg: "26px" }}>

        <SalesOverview
          title={"Requests / Second (15 Minute Window)"}
          chart={<LineChartV2 data={requests_per_second}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Second (15 Minute Window)"}
          chart={<LineChartV2 data={avg_latency_per_second}/>}
        /> 

        <SalesOverview
          title={"Requests / Minute (15 Minute Window)"}
          chart={<LineChartV2 data={requests_per_minute}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Minute (15 Minute Window)"}
          chart={<LineChartV2 data={avg_latency_per_minute}/>}
        /> 

        <SalesOverview
          title={"Requests Distribution"}
          percentage={undefined}
          chart={<DonutChart series={total_requests.values} 
            options={{
              labels: total_requests.keys,
              legend: {
                position: 'bottom',
              }
            }}/>}
        />

        <SalesOverview
          title={"Errors Distribution"}
          percentage={undefined}
          chart={<DonutChart series={all_errors.values} 
            options={{
              labels: all_errors.keys,
              legend: {
                position: 'bottom',
              }
            }}/>}
        />

      </Grid>

    </Flex>
  );

}