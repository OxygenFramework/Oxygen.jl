# Cron Scheduling 

Oxygen comes with a built-in cron scheduling system that allows you to call endpoints and functions automatically when the cron expression matches the current time.

When a job is scheduled, a new task is created and runs in the background. Each task uses its given cron expression and the current time to determine how long it needs to sleep before it can execute.

The cron parser in Oxygen is based on the same specifications as the one used in Spring. You can find more information about this on the [Spring Cron Expressions](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/support/CronExpression.html) page.

## Cron Expression Syntax
The following is a breakdown of what each parameter in our cron expression represents. While our specification closely resembles the one defined by Spring, it's not an exact 1-to-1 match.
```
The string has six single space-separated time and date fields:

 ┌───────────── second (0-59)
 │ ┌───────────── minute (0 - 59)
 │ │ ┌───────────── hour (0 - 23)
 │ │ │ ┌───────────── day of the month (1 - 31)
 │ │ │ │ ┌───────────── month (1 - 12) (or JAN-DEC)
 │ │ │ │ │ ┌───────────── day of the week (1 - 7)
 │ │ │ │ │ │          (Monday is 1, Tue is 2... and Sunday is 7)
 │ │ │ │ │ │
 * * * * * *
```
Partial expressions are also supported, which means that subsequent expressions can be left out (they are defaulted to `'*'`). 

```julia
# In this example we see only the `seconds` part of the expression is defined. 
# This means that all following expressions are automatically defaulted to '*' expressions
@cron "*/2" function()
    println("runs every 2 seconds")
end
```

## Scheduling Endpoints

The `router()` function has a keyword argument called `cron`, which accepts a cron expression that determines when an endpoint is called. Just like the other keyword arguments, it can be reused by endpoints that share routers or be overridden by inherited endpoints.

```julia
# execute at 8, 9 and 10 o'clock of every day.
@get router("/cron-example", cron="0 0 8-10 * * *") function(req)
    println("here")
end

# execute this endpoint every 5 seconds (whenever current_seconds % 5 == 0)
every5 = router("/cron", cron="*/5")

# this endpoint inherits the cron expression
@get every5("/first") function(req)
    println("first")
end

# Now this endpoint executes every 2 seconds ( whenever current_seconds % 2 == 0 ) instead of every 5
@get every5("/second", cron="*/2") function(req)
    println("second")
end
```

## Scheduling Functions

In addition to scheduling endpoints, you can also use the new `@cron` macro to schedule functions. This is useful if you want to run code at specific times without making it visible or callable in the API.

```julia
@cron "*/2" function()
    println("runs every 2 seconds")
end

@cron "0 0/30 8-10 * * *" function()
  println("runs at 8:00, 8:30, 9:00, 9:30, 10:00 and 10:30 every day")
end
```

## Starting & Stopping Cron Jobs

When you run `serve()` or `serveparallel()`, all registered cron jobs are automatically started. If the server is stopped or killed, all running jobs will also be terminated. You can stop the server and all repeat tasks and cron jobs by calling the `terminate()` function or manually killing the server with `ctrl+C`.

In addition, Oxygen provides utility functions to manually start and stop cron jobs: `startcronjobs()` and `stopcronjobs()`. These functions can be used outside of a web server as well.