import React from "react";
// Chakra imports
import {
  Flex,
  Grid,
  SimpleGrid,
  useColorModeValue,
  Box, 
  Text,
  Heading,
  Checkbox,
  Stack,
  HStack,
  Switch,
  Select,
  FormControl,
  FormLabel,
  useDisclosure
} from "@chakra-ui/react";

import moment from "moment";

// charts
import { DonutChart } from "components/Charts/DonutChart";
import { LineChartV2 } from "components/Charts/LineChartV2";
import { BrushChart } from "components/Charts/BrushChart";

// Custom icons
import { useHookstate } from '@hookstate/core';
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
  const fillDataGaps = state.dashboard.fill_gaps.get();
  const window_value = state.dashboard.window.get();
  const chart_range = window_value == "null" ? undefined : parseInt(window_value) *  60 * 1000;

  const server = state.metrics.server.get();
  const {
    avg_latency_per_minute,
    requests_per_minute,
    avg_latency_per_second,
    requests_per_second
  } = state.metrics.get();

 
  function fill_data(data, unit=1000){
    return fillMissingData(Array.from(data).map(x => [...x]), unit, true, false);
  }

  function dict_to_array(dict) {
    return Array.from(dict).map(item => [...item]);
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

      <Heading size="md" mb="5">Server Metrics</Heading>

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
        my='15px'
        gap='15px'>
      </Grid>

      <Grid
        templateColumns={{ sm: "1fr", lg: "1.5fr 1.5fr" }}
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

      <Box display="flex" justifyContent="space-between" alignItems="center" height="60px"> {/* Ensure a height is set */}
        <Heading size="md">Performance Insights</Heading>
        
        <Box display="flex" justifyContent="space-between" gap="15px">
          <Checkbox 
            isChecked={fillDataGaps}
            onChange={(e) => state.dashboard.fill_gaps.set(p => !p)}
          >Fill Gaps</Checkbox>
          <Select
            onChange={(e) => state.dashboard.window.set(e.target.value)}
            value={window_value} 
            size='md' width={140} 
            >
            <option value={1}>1 minute</option>
            <option value={5}>5 minute</option>
            <option value={10}>10 minute</option>
            <option value={15}>15 minutes</option>
            <option value={30}>30 minutes</option>
            <option value={60}>1 hour</option>
            <option value={60 * 6}>6 hours</option>
            <option value={60 * 12}>12 hours</option>
            <option value={60 * 24}>24 hours</option>
            <option value={"null"}>All</option>
          </Select>
        </Box>
        
      </Box>

      <Grid
        templateColumns={{ sm: "1fr", lg: "1.5fr 1.5fr" }}
        templateRows={{ sm: "repeat(2, 1fr)", lg: "1fr" }}
        gap='24px'
        mb={{ lg: "26px" }}>

        <SalesOverview
          title={"Requests / Second"}
          chart={
            <BrushChart 
              range={chart_range}
              data={fillDataGaps ? fill_data(requests_per_second) : dict_to_array(requests_per_second)} 
            />
          }
        />  

        <SalesOverview
          title={"Avg Latency / Second"}
          chart={
            <BrushChart 
              range={chart_range}
              data={fillDataGaps ? fill_data(avg_latency_per_second) : dict_to_array(avg_latency_per_second)}
            />
          }
        /> 

        <SalesOverview
          title={"Requests / Minute"}
          chart={
            <LineChartV2 
              range={chart_range}
              data={fillDataGaps ? fill_data(requests_per_minute, 60_000) : dict_to_array(requests_per_minute)}
            />
          }
        /> 

        <SalesOverview
          title={"Avg Latency / Minute"}
          chart={
            <LineChartV2 
              range={chart_range}
              data={fillDataGaps ? fill_data(avg_latency_per_minute, 60_000) : dict_to_array(avg_latency_per_minute)}
            />
          }
        /> 

      </Grid>

    </Flex>
  );

}