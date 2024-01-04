

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
    avg_latency_per_second: Map<Date, Number>
    requests_per_second: Map<Date, Number>
    requests_per_minute: Map<Date, Number>
    avg_latency_per_minute: Map<Date, Number>
}

export interface AppState {
    metrics: Metrics
    dashboard: {
        window: string
        fill_gaps: boolean
    },
    settings: {
        poll: boolean,
        interval: number
    }
}

const defaultState: AppState = {
    dashboard: {
        window: "15",  // number of minutes for our window
        fill_gaps: true
    },
    settings: {
        poll: true,
        interval: 3
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