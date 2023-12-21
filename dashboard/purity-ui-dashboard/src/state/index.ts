

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
    bins: TimedBins[]
    endpoints: Endpoints
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
        bins: [],
        endpoints: {}
    }
}

export const globalState = hookstate(defaultState);

export function setMetrics(metrics: Metrics){
    globalState.metrics.set({...metrics});
}

export function getMetrics(){
    return globalState.metrics.get()
}