

import React from 'react';
import { hookstate } from '@hookstate/core';

interface Stats {
    percentile_latency_95th: number
    avg_latency: number
    max_latency: number
    total_requests: number
    min_latency: number
    error_rate: number
}
interface Transaction {
    ip: string
    uri: string
    timestamp: Date
    duration: number
    success: boolean
    status: number,
    error_message: null | string
}

interface Endpoints {
    [name: string]: Stats;
}

interface Metrics {
    server: Stats
    endpoints: Endpoints
    errors: Map<String,Number>
    avg_latency_per_second: []
    requests_per_second: []
    requests_per_minute: []
    avg_latency_per_minute: []
}

export interface AppState {
    metrics: Metrics
    dashboard: {
        window: string
        fill_gaps: boolean
        latestData: string
    },
    settings: {
        poll: boolean,
        interval: number
    }
}

const defaultState: AppState = {
    dashboard: {
        window: "15",  // number of minutes for our window
        fill_gaps: true,
        latestData: "null"
    },
    settings: {
        poll: true,
        interval: 3,
    },
    metrics: {
        server: {
            percentile_latency_95th: NaN,
            avg_latency: NaN,
            max_latency: NaN,
            total_requests: NaN,
            min_latency: NaN,
            error_rate: NaN
        },
        endpoints: {},
        errors: new Map(),
        avg_latency_per_second: [],
        requests_per_second: [],
        requests_per_minute: [],
        avg_latency_per_minute: []
    }
}

export const globalState = hookstate(defaultState);

export function setMetrics(metrics: Metrics){
    globalState.metrics.set({...metrics});
}

function mergeTimeseries<T>(prevData: T[], newData: T[]): T[]{
    return removeDuplicates(prevData.concat(newData))
}

function removeDuplicates(data) {
    const seen = new Map();
    const result = [];
    for (let i = 0; i < data.length; i++) {
      const item = data[i];
      const key = item[0]; // Use only the date-time as the key
  
      if (seen.has(key)) {
        // If the key is already seen, update the corresponding item in the result
        result[seen.get(key)][1] = item[1];
      } else {
        // If it's a new key, add it to the result and mark its index
        seen.set(key, result.length);
        result.push(item);
      }
    }
    return result;
}

  
export function appendMetrics(metrics: Metrics){
    globalState.metrics.set(prev => {
        return {
            // overwrite previous metrics instead of append
            server: metrics.server, 
            endpoints: metrics.endpoints,
            errors: metrics.errors,

            // append
            requests_per_second: mergeTimeseries(prev.requests_per_second, metrics.requests_per_second),
            avg_latency_per_second: mergeTimeseries(prev.avg_latency_per_second,  metrics.avg_latency_per_second),
            
            requests_per_minute: mergeTimeseries(prev.requests_per_minute, metrics.requests_per_minute),
            avg_latency_per_minute: mergeTimeseries(prev.avg_latency_per_minute, metrics.avg_latency_per_minute),
        }
    });
}

export function getMetrics(){
    return globalState.metrics.get()
}