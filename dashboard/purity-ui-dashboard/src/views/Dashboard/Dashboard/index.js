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
  // const {server, history, endpoints} = getMetrics();

  const state = useHookstate(globalState);

  const server = state.metrics.server.get();
  const {
    avg_latency_per_minute,
    requests_per_minute,
    avg_latency_per_second,
    requests_per_second
  } = state.metrics.get();
  // const requests_per_second = state.metrics.requests_per_second.get()
  // const avg_latency_per_second = state.metrics.avg_latency_per_second.get()

  const total_requests = Object.entries(state.metrics.endpoints.get() || {})?.reduce((acc, item) => {
        let [k,v] = item;
        acc.keys.push(k);
        acc.values.push(v.total_requests);
        return acc;

    }, {keys: [], values: []}
  )

  function timeseries(data){
    // Convert the data into an array of [timestamp, value] pairs
    return Object.entries(data)
            .map(item => [new Date(item[0]).getTime(), item[1]])
            .sort((a, b) => a[0] - b[0])
  }

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
          title={"Requests / Minute (15 Minute Window)"}
          chart={ <LineChartV2 data={timeseries(requests_per_minute)}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Minute (15 Minute Window)"}
          chart={ <LineChartV2 data={timeseries(avg_latency_per_minute)}/>}
        /> 

        <SalesOverview
          title={"Requests / Second (15 Minute Window)"}
          chart={ <LineChartV2 data={timeseries(requests_per_second)}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Second (15 Minute Window)"}
          chart={<LineChartV2 data={timeseries(avg_latency_per_second)}/>}
        /> 

        {/* <ActiveUsers
          title={"Active Users"}
          percentage={23}
          chart={<BarChart />}
        />
        <SalesOverview
          title={"Sales Overview"}
          percentage={5}
          chart={<LineChart />}
        /> */}

      </Grid>

    </Flex>
  );

}