

import React from 'react';
import { hookstate, useHookstate, ImmutableObject} from '@hookstate/core';


interface TimedBins {
    timestamp: Date
    count: number
}

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
    sucess: boolean
    status: number,
    error_message: null | string
}

interface Endpoints {
    [name: string]: Stats;
}


interface Metrics {
    server: Stats
    endpoints: Endpoints
    avg_latency_per_second: Map<Date, Number>
    requests_per_second: Map<Date, Number>
    requests_per_minute: Map<Date, Number>
    avg_latency_per_minute: Map<Date, Number>
}

export interface AppState {
    metrics: Metrics
}

const defaultState: AppState = {
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
        avg_latency_per_second: new Map(),
        requests_per_second: new Map(),
        requests_per_minute: new Map(),
        avg_latency_per_minute:  new Map()
    }
}

export const globalState = hookstate(defaultState);

export function setMetrics(metrics: Metrics){
    globalState.metrics.set({...metrics});
}

export function getMetrics(){
    return globalState.metrics.get()
}