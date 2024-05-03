module Cron
using Base: @kwdef
using Dates

using ..Types: ActiveCron, RegisteredCron, Nullable
using ..AppContext: CronContext

export cron, startcronjobs, stopcronjobs, clearcronjobs

"""
Builds a new CRON job definition and appends it to hte list of cron jobs
"""
function cron(cronjobs::Set{RegisteredCron}, expression::String, name::String, f::Function)
    job_id = hash((expression, name, f))
    job = RegisteredCron(job_id, expression, name, f)
    push!(cronjobs, job)
end

"""
    stopcronjobs()

Stop each background task by toggling a global reference that all cron jobs reference
"""
function stopcronjobs(cron::CronContext)
    cron.run[] = false
    # clear the set of all running job ids
    empty!(cron.active_jobs)
end

"""
Clears all cron job defintions
"""
function clearcronjobs(cron::CronContext)
    # clear all job definitions
    empty!(cron.registered_jobs)
end


"""
    startcronjobs()
    
Start all the cron cronjobs within their own async task. Each individual task will loop conintually 
and sleep untill the next time it's suppost to 
"""
function startcronjobs(cron::CronContext)
    
    if isempty(cron.registered_jobs)
        return 
    end

    # set the global run flag to true
    cron.run[] = true

    # pull out all ids for the current running tasks
    running_tasks = Set{UInt}(job.id for job in cron.active_jobs)

    # filter out any jobs that are already running
    filtered_jobs = filter(cron.registered_jobs) do cronjob
        # (job_id, expression, name, func) = cronjob
        if cronjob.id in running_tasks
            printstyled("[ Cron: $(cronjob.name) is already running\n", color = :yellow)
            return false
        else
            return true
        end
    end

    # exit function early if no jobs to start
    if isempty(filtered_jobs)
        return
    end

    println()
    printstyled("[ Starting $(length(filtered_jobs)) Cron Job(s)\n", color = :green, bold = true)  

    for job in filtered_jobs

        job_id, expression, name, func = job.id, job.expression, job.name, job.action

        # add job it to set of running jobs
        push!(cron.active_jobs, ActiveCron(job_id, job))

        printstyled("[ Cron: ", color = :green, bold = true)  
        println("{ expr: $expression, name: $name }")
        # Assuming name and expression are your variables
        Threads.@spawn begin
            try 
                while cron.run[]
                    # get the current datetime object
                    current_time::DateTime = now()
                    # get the next datetime object that matches this cron expression
                    next_date = next(expression, current_time)
                    # figure out how long we need to wait
                    ms_to_wait = sleep_until(current_time, next_date)
                    # breaking the sleep into 1-second intervals
                    while ms_to_wait > 0 && cron.run[]
                        sleep_time = min(1000, ms_to_wait)  # Sleep for 1 second or the remaining time
                        sleep(Millisecond(sleep_time))
                        ms_to_wait -= sleep_time  # Reduce the wait time
                    end
                    # Execute the function if it's time and if we are still running
                    if ms_to_wait <= 0 && cron.run[]
                        try 
                            @async func() # for ordinary functions
                        catch error 
                            @error "ERROR in CRON job { id: $job_id, expr: $expression, name: $name }: " exception=(error, catch_backtrace())
                        end
                    end
                end
            finally
                # remove job id if the job fails
                delete!(cron.active_jobs, job_id)
            end
        end
        
    end
end

weeknames = Dict(
    "SUN" => 7,
    "MON" => 1,
    "TUE" => 2,
    "WED" => 3,
    "THU" => 4,
    "FRI" => 5,
    "SAT" => 6,
)

monthnames = Dict(
    "JAN" => 1,
    "FEB" => 2,
    "MAR" => 3,
    "APR" => 4,
    "MAY" => 5,
    "JUN" => 6,
    "JUL" => 7,
    "AUG" => 8,
    "SEP" => 9,
    "OCT" => 10,
    "NOV" => 11,
    "DEC" => 12
)

function translate(input::AbstractString)
    if haskey(weeknames, input)
        return weeknames[input]
    elseif haskey(monthnames, input)
        return monthnames[input]
    else 
        return input
    end
end


function customparse(type, input)
    if isa(input, type)
        return input
    end 
    return parse(type, input)
end

# https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/support/CronExpression.html
# https://crontab.cronhub.io/


"""
return the date for the last weekday (Friday) of the month
"""
function lastweekdayofmonth(time::DateTime)
    current = lastdayofmonth(time)
    while dayofweek(current) > 5
        current -= Day(1)
    end
    return current
end

function isweekday(time::DateTime)
    daynumber = dayofweek(time)
    return daynumber >= 1 && daynumber <= 5
end

"""
Return the date of the weekday that's nearest to the nth day of the month
"""
function nthweekdayofmonth(time::DateTime, n::Int64)
    if n < 1 || n > Dates.daysinmonth(time)
        error("n must be between 1 and $(Dates.daysinmonth(time))")
    end

    target = DateTime(year(time), month(time), day(n))
    if isweekday(target)
        return target
    end

    current_month = month(time)
    before = DateTime(year(time), month(time), day(max(1, n-1)))
    after = DateTime(year(time), month(time), day(min(n+1, Dates.daysinmonth(time))))

    while true
        if isweekday(before) && month(before) == current_month
            return before
        elseif isweekday(after) && month(after) == current_month
            return after
        end
        if day(after) < Dates.daysinmonth(time)
            after += Day(1)
        else
            break
        end
    end
end

"""
return the date for the last weekday (Friday) of the week
"""
function lastweekday(time::DateTime)
    current = lastdayofweek(time)
    while dayofweek(current) > 5
        current -= Day(1)
    end
    return current
end

function lasttargetdayofmonth(time::DateTime, daynumber::Int64)
    last_day = lastdayofmonth(time)
    current = DateTime(year(last_day), month(last_day), day(Dates.daysinmonth(time)))
    while dayofweek(current) != daynumber
        current -= Day(1)
    end
    return current
end

function getoccurance(time::DateTime, daynumber::Int64, occurance::Int64)
    baseline = firstdayofmonth(time) 
    # increment untill we hit the daytype we want 
    while dayofweek(baseline) !== daynumber
        baseline += Day(1)
    end

    # keep jumping by 7 days untill we the the target occurance
    while dayofweekofmonth(baseline) !== occurance
        baseline += Day(7)
    end

    return baseline
end


function matchexpression(input::Nullable{AbstractString}, time::DateTime, converter, maxvalue, adjustedmax=nothing) :: Bool
    try 
            
        # base case: return true if 
        if isnothing(input)
            return true
        end

        # Handle sole week or month expressions
        if haskey(weeknames, input) || haskey(monthnames, input)
            input = translate(input)
        end 

        numericvalue = isa(input, Int64) ? input : tryparse(Int64, input)

        current = converter(time)

        # need to convert zero based max values to their "real world" equivalent
        if !isnothing(adjustedmax) && current == 0 
            current = adjustedmax
        end

        # Every Second
        if input == "*" 
            return true 
        # At X seconds past the minute
        elseif numericvalue !== nothing
            # If this field is zero indexed and set to 0
            if !isnothing(adjustedmax) && current == adjustedmax
                return numericvalue == (current - adjustedmax)
            else
                return numericvalue == current
            end

        elseif contains(input, ",")
            lowerbound, upperbound = split(input, ",")
            lowerbound, upperbound = translate(lowerbound), translate(upperbound)
            return current == customparse(Int64, lowerbound) || current === customparse(Int64, upperbound)

        elseif contains(input, "-")
            lowerbound, upperbound = split(input, "-")
            lowerbound, upperbound = translate(lowerbound), translate(upperbound)

            if lowerbound == "*"
                return current <= customparse(Int64, upperbound)
            elseif upperbound == "*"
                return current >= customparse(Int64, lowerbound)
            else 
                return current >= customparse(Int64, lowerbound) && current <= customparse(Int64, upperbound)
            end
            
        elseif contains(input, "/")
            numerator, denominator = split(input, "/")
            numerator, denominator = translate(numerator), translate(denominator)
            # Every second, starting at Y seconds past the minute
            if denominator == "*"
                numerator = customparse(Int64, numerator)
                return current >= numerator
            elseif numerator == "*"
                # Every X seconds
                denominator = customparse(Int64, denominator)
                return current % denominator == 0
            else
                # Every X seconds, starting at Y seconds past the minute
                numerator = customparse(Int64, numerator)
                denominator = customparse(Int64, denominator)
                return current % denominator == 0 && current >= numerator
            end
        end

        return false
    catch 
        return false 
    end
end


function match_special(input::Nullable{AbstractString}, time::DateTime, converter, maxvalue, adjustedmax=nothing) :: Bool
    
    # base case: return true if 
    if isnothing(input)
        return true
    end

    # Handle sole week or month expressions
    if haskey(weeknames, input) || haskey(monthnames, input)
        input = translate(input)
    end 
    
    numericvalue = isa(input, Int64) ? input : tryparse(Int64, input)
    current = converter(time)

    # if given a datetime as a max value, means this is a special case expression
    if maxvalue isa Function 
        maxvalue = converter(maxvalue(time))
    end

    current = converter(time)

    # need to convert zero based max values to their "real world" equivalent
    if !isnothing(adjustedmax) && current == 0 
        current = adjustedmax
    end

    # At X seconds past the minute
    if numericvalue !== nothing
        # If this field is zero indexed and set to 0
        if !isnothing(adjustedmax) && current == adjustedmax
            return numericvalue == (current - adjustedmax)
        else
            return numericvalue == current
        end

    elseif input == "?" || input == "*"
        return true 

    # comamnd: Return the last valid value for this field
    elseif input == "L"
        return current == maxvalue   

    # command: the last weekday of the month
    elseif input == "LW"
        return current == converter(lastweekdayofmonth(time))

    # command negative offset (i.e. L-n), it means "nth-to-last day of the month".  
    elseif contains(input, "L-")
        return current == maxvalue - customparse(Int64, replace(input, "L-" => ""))
        
    # ex.) "11W" = on the weekday nearest day 11th of the month
    elseif match(r"[0-9]+W", input) !== nothing
        daynumber = parse(Int64, replace(input, "W" => ""))
        return current == dayofmonth(nthweekdayofmonth(time, daynumber))

    # ex.) "4L" = last Thursday of the month
    elseif match(r"[0-9]+L", input) !== nothing
        daynumber = parse(Int64, replace(input, "L" => ""))
        return dayofmonth(time) == dayofmonth(lasttargetdayofmonth(time, daynumber))
        
    # ex.) "THUL" = last Thursday of the month
    elseif match(r"([A-Z]+)L", input) !== nothing
        dayabbreviation = match(r"([A-Z]+)L", input)[1]
        daynumber = weeknames[dayabbreviation]
        return dayofmonth(time) == dayofmonth(lasttargetdayofmonth(time, daynumber))

    # ex.) 5#2" = the second Friday in the month
    elseif match(r"([0-9])#([0-9])", input) !== nothing      
        daynumber, position = match(r"([0-9])#([0-9])", input).captures
        target = getoccurance(time, parse(Int64, daynumber), parse(Int64, position))
        return dayofmonth(time) == dayofmonth(target)

    # ex.) "MON#1" => the first Monday in the month
    elseif match(r"([A-Z]+)#([0-9])", input) !== nothing
        daynumber, position = match(r"([A-Z]+)#([0-9])", input).captures
        target = getoccurance(time, weeknames[daynumber], parse(Int64, position))
        return dayofmonth(time) == dayofmonth(target)
    else
        return false
    end

end


function iscronmatch(expression::String, time::DateTime) :: Bool
    parsed_expression::Vector{Nullable{AbstractString}} = split(strip(expression), " ")

    # fill in any missing arguments with nothing, so the array is always 
    fill_length = 6 - length(parsed_expression)
    if fill_length > 0
        parsed_expression = vcat(parsed_expression, fill(nothing, fill_length))
    end
    
    # extract individual expressions
    seconds_expression, minute_expression, hour_expression,
    dayofmonth_expression, month_expression, dayofweek_expression = parsed_expression

    if !match_month(month_expression, time)
        return false
    end

    if !match_dayofmonth(dayofmonth_expression, time)
        return false
    end
    
    if !match_dayofweek(dayofweek_expression, time)
        return false 
    end

    if !match_hour(hour_expression, time)
        return false 
    end

    if !match_minutes(minute_expression, time)
        return false
    end

    if !match_seconds(seconds_expression, time)
        return false
    end

    return true 
end


function match_seconds(seconds_expression, time::DateTime)
    return matchexpression(seconds_expression, time, second, 59, 60)
end

function match_minutes(minute_expression, time::DateTime)
    return matchexpression(minute_expression, time, minute, 59, 60)
end

function match_hour(hour_expression, time::DateTime)
    return matchexpression(hour_expression, time, hour, 23, 24)
end

function match_dayofmonth(dayofmonth_expression, time::DateTime)
    return match_special(dayofmonth_expression, time, dayofmonth, lastdayofmonth) || matchexpression(dayofmonth_expression, time, dayofmonth, lastdayofmonth)
end

function match_month(month_expression, time::DateTime)
    return match_special(month_expression, time, month, 12) || matchexpression(month_expression, time, month, 12)
end

function match_dayofweek(dayofweek_expression, time::DateTime)
    return match_special(dayofweek_expression, time, dayofweek, lastdayofweek) || matchexpression(dayofweek_expression, time, dayofweek, lastdayofweek)
end


"""
This function takes a cron expression and a start_time and returns the next datetime object that matches this 
expression
"""
function next(cron_expr::String, start_time::DateTime)::DateTime

    parsed_expression::Vector{Nullable{AbstractString}} = split(strip(cron_expr), " ")

    # fill in any missing arguments with nothing, so the array is always 
    fill_length = 6 - length(parsed_expression)
    if fill_length > 0
        parsed_expression = vcat(parsed_expression, fill(nothing, fill_length))
    end
        
    # extract individual expressions
    seconds_expression, minute_expression, hour_expression,
    dayofmonth_expression, month_expression, dayofweek_expression = parsed_expression

    # initialize a candidate time with start_time plus one second 
    candidate_time = start_time + Second(1)

    # loop until candidate time matches all fields of cron expression 
    while true

        # check if candidate time matches second field
        if !match_seconds(seconds_expression, candidate_time)
            # increment candidate time by one second
            candidate_time += Second(1)
            continue
        end

        # check if candidate time matches minute field
        if !match_minutes(minute_expression, candidate_time)
            # increment candidate time by one minute and reset second
            # to minimum value
            candidate_time += Minute(1) - Second(second(candidate_time))
            continue
        end

        # check if candidate time matches hour field 
        if !match_hour(hour_expression, candidate_time)
            # increment candidate time by one hour and reset minute
            # and second to minimum values 
            candidate_time += Hour(1) - Minute(minute(candidate_time)) -
                                Second(second(candidate_time))
            continue 
        end

        # check if candidate time matches day of week field 
        if !match_dayofweek(dayofweek_expression, candidate_time)
            # increment candidate time by one day and reset hour,
            # minute and second to minimum values 
            candidate_time += Day(1) - Hour(hour(candidate_time)) -
                                Minute(minute(candidate_time)) -
                                Second(second(candidate_time))
            continue 
        end

        # check if candidate time matches day of month field 
        if !match_dayofmonth(dayofmonth_expression, candidate_time)
            # increment candidate time by one day and reset hour,
            # minute and second to minimum values 
            candidate_time += Day(1) - Hour(hour(candidate_time)) -
                                Minute(minute(candidate_time)) -
                                Second(second(candidate_time))
            continue 
        end

        # check if candidate time matches month field 
        if !match_month(month_expression, candidate_time)
            # increment candidate time by one month and reset day, hour,
            # minute and second to minimum values 
            candidate_time += Month(1) - Day(day(candidate_time)) + Day(1) -
                                Hour(hour(candidate_time)) -
                                Minute(minute(candidate_time)) -
                                Second(second(candidate_time))
            continue 
        end

        break # exit the loop as all fields match
    end 
    return remove_milliseconds(candidate_time) # return the next matching tme
end 

# remove the milliseconds from a datetime by rounding down at the seconds
function remove_milliseconds(dt::DateTime)
    return floor(dt, Dates.Second)
end

function sleep_until(now::DateTime, future::DateTime)
    # Check if the future datetime is later than the current datetime
    if future > now
        # Convert the difference between future and now to milliseconds
        ms = Dates.value(future - now)
        # Return the milliseconds to sleep
        return ms
    else
        # Return zero if the future datetime is not later than the current datetime
        return 0
    end
end

end 
