// Chakra imports
import {
  Flex,
  Grid,
  SimpleGrid,
  useColorModeValue,
  Stack,
  HStack,
  Switch,
  Select,
  FormControl,
  FormLabel,
  useDisclosure
} from "@chakra-ui/react";
// assets
import { DonutChart } from "components/Charts/DonutChart";
import { LineChartV2 } from "components/Charts/LineChartV2";
// Custom icons
import { useHookstate } from '@hookstate/core';
import React from "react";
import { globalState } from "../../../state/index.ts";
import MiniStatistics from "./components/MiniStatistics";
import SalesOverview from "./components/SalesOverview";
import { fillMissingData } from "./util";

import { CiGlobe } from "react-icons/ci";
import { IoMdPodium } from "react-icons/io";
import { IoTimerOutline, IoWarningOutline } from "react-icons/io5";
import { RiArrowDownDoubleLine, RiArrowUpDoubleLine } from "react-icons/ri";

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
  
  function fill_data(data, unit=1000){
    return fillMissingData(Array.from(data).map(x => [...x]), unit);
  }

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
          amount={server.total_requests.toLocaleString()}
          percentage={undefined}
          icon={<CiGlobe color={iconBoxInside} style={{ width: '24px', height: '24px' }}/>}
        />
        <MiniStatistics
          title={"Error Rate"}
          amount={(server.error_rate * 100).toFixed(2) + "%"}
          percentage={undefined}
          icon={<IoWarningOutline color={iconBoxInside} style={{ width: '24px', height: '24px' }}/>}
        />
        <MiniStatistics
          title={"Avg Latency"}
          amount={(server.avg_latency * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<IoTimerOutline color={iconBoxInside} style={{ width: '24px', height: '24px' }} />}
        />
        <MiniStatistics
          title={"95th Percentile Latency"}
          amount={(server.percentile_latency_95th * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<IoMdPodium color={iconBoxInside} style={{ width: '24px', height: '24px' }} />}
        />
        <MiniStatistics
          title={"Min Latency"}
          amount={(server.min_latency  * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<RiArrowDownDoubleLine color={iconBoxInside} style={{ width: '24px', height: '24px' }} />}
        />
        <MiniStatistics
          title={"Max Latency"}
          amount={(server.max_latency  * 1000).toFixed(2) + "ms"}
          percentage={undefined}
          icon={<RiArrowUpDoubleLine color={iconBoxInside} style={{ width: '24px', height: '24px' }} />}
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
          chart={<LineChartV2 data={fill_data(requests_per_second)}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Second (15 Minute Window)"}
          chart={<LineChartV2 data={fill_data(avg_latency_per_second)}/>}
        /> 

        <SalesOverview
          title={"Requests / Minute (15 Minute Window)"}
          chart={<LineChartV2 data={fill_data(requests_per_minute, 60_000)}/>}
        /> 

        <SalesOverview
          title={"Avg Latency / Minute (15 Minute Window)"}
          chart={<LineChartV2 data={fill_data(avg_latency_per_minute, 60_000)}/>}
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