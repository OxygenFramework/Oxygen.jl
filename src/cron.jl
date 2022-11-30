module Cron

using Dates
export @cron, startcronjobs, stopcronjobs, resetcronstate

global const jobs = Ref{Vector}([])
global const stop = Ref{Bool}(false)

"""
Registers a function with a cron expression
"""
macro cron(expression, func)
    quote 
        local job = ($(esc(expression)), $(esc(func)))
        push!($jobs[], job)
    end
end

"""
Stop all cron jobs 
"""
function stopcronjobs()
    stop[] = true
    jobs[] = []
end

"""
Reset the globals in this module 
"""
function resetcronstate()
    jobs[] = []
    stop[] = false
end

"""
Starts all cronjobs. This function kicks off an async task that executes every second
and iterates over all cron expressions to determine whether it needs to get run or not.
Each registered function is called asynchronously so we don't slow down the time-sync loop. 
"""
function startcronjobs()

    if isempty(jobs)
        return 
    end

    @async begin
        # spin until our cpu hits a whole second
        previoustime::Union{DateTime, Nothing} = nothing
        while !stop[]
            # execute code on every whole second
            current_time::DateTime = now()
            if previoustime !== current_time && millisecond(current_time) == 0
                @async for (expression, func) in jobs[]
                    if iscronmatch(expression, current_time)
                        func()
                    end
                end
            end
            previoustime = current_time
            yield()
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

function translate(input::SubString)
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

    target = DateTime(year(time), month(time), day(n))
    if isweekday(target)
        return target
    end

    before = DateTime(year(time), month(time), day(n-1))
    after = DateTime(year(time), month(time), day(n+1))

    while true 
        if isweekday(before)
            return before
        elseif isweekday(after)
            return after
        end 
        before -= Day(1)
        after += Day(1)
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
    current = lastdayofmonth(time)
    while dayofweek(current) !== daynumber
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

function matchexpression(input::Union{SubString,Nothing}, time::DateTime, converter, maxvalue, adjustedmax=nothing) :: Bool
    
    # base case: return true if 
    if isnothing(input)
        return true
    end

    # Handle sole week or month expressions
    if haskey(weeknames, input) || haskey(monthnames, input)
        input = translate(input)
    end

    numericvalue = isa(input, Int64) ? input : tryparse(Int64, input)

    # if given a datetime as a max value, means this is a special case expression
    special_case = false
    if maxvalue isa Function 
        maxvalue = converter(maxvalue(time))
        special_case = true
    end

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
            # ensure they cancel each other out (should equal zero)
            return numericvalue == (current - adjustedmax)
        else
            return numericvalue == current
        end

    elseif special_case

        if input == "?"
            return true 

        # comamnd: Return the last valid value for this field
        elseif input == "L"
            return current == maxvalue   

        # command: the last weekday of the month
        elseif input == "LW"
            return current == converter(lastweekdayofmonth(time))

        # command negative offset (i.e. L-n), it means "nth-to-last day of the month".  
        elseif contains(input, "L-")
            return current >= maxvalue - customparse(Int64, replace(input, "L-" => ""))
            
        # ex.) "11W" = on the weekday nearest day 11th of the month
        elseif match(r"[0-9]+W", input) !== nothing
            daynumber = parse(Int64, replace(input, "W" => ""))
            return current == dayofmonth(nthweekdayofmonth(time, daynumber))

        # ex.) "4L" = last Thursday of the month
        elseif match(r"[0-9]+L", input) !== nothing
            daynumber = parse(Int64, replace(input, "L" => ""))
            return current == converter(lasttargetdayofmonth(time, daynumber))

        # ex.) "THUL" = last Thursday of the month
        elseif match(r"([A-Z]+)L", input) !== nothing
            dayabbreviation = match(r"([A-Z]+)L", input)[1]
            daynumber = weeknames[dayabbreviation]
            return current == converter(lasttargetdayofmonth(time, daynumber))

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
end


function iscronmatch(expression::String, time::DateTime) :: Bool
    parsed_expression::Vector{Union{Nothing, SubString{String}}} = split(strip(expression), " ")

    # fill in any missing arguments with nothing, so the array is always 
    fill_length = 6 - length(parsed_expression)
    if fill_length > 0
        parsed_expression = vcat(parsed_expression, fill(nothing, fill_length))
    end
    
    # extract individual expressions
    seconds_expression, minute_expression, hour_expression,
    dayofmonth_expression, month_expression, dayofweek_expression = parsed_expression

    if !matchexpression(seconds_expression, time, second, 59, 60)
        return false
    end

    if !matchexpression(minute_expression, time, minute, 59, 60)
        return false
    end

    if !matchexpression(hour_expression, time, hour, 23, 24)
        return false 
    end

    if !matchexpression(dayofmonth_expression, time, dayofmonth, lastdayofmonth)
        return false
    end

    if !matchexpression(month_expression, time, month, 12)
        return false
    end

    if !matchexpression(dayofweek_expression, time, dayofweek, lastdayofweek)
        return false 
    end

    return true 
end

end 