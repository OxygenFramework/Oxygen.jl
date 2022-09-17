module Cron

using Dates

function everysecond(func)
    # spin until our cpu hits a whole second
    # @async begin 
        previoustime::Union{DateTime, Nothing} = nothing
        while true
            # execute code on every whole second
            current_time::DateTime = now()
            if previoustime !== current_time && millisecond(current_time) == 0
                func(current_time)
            end
            previoustime = current_time
        end 
    # end
end


weeknames = Dict(
    "SUN" => 0,
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
        return weeknames[input]
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

function matchPrimitives(input::SubString, time::DateTime, converter) :: Bool
    current = converter(time)
    numericvalue = tryparse(Int64, input)

    # Every Second
    if input == "*"
        return true 

    # At X seconds past the minute
    elseif numericvalue !== nothing
        return numericvalue == current

    # Handle sole week or month name expressions
    elseif haskey(weeknames, input) || haskey(monthnames, input)
        return translate(input)

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
    else 
        return false
    end
end

cron = "* 34-35 23 * * MON-WED" # every 10 seconds
function run(time:: DateTime)
    seconds_expression, minute_expression, hour_expression,
    dayofmonth_expression, month_expression, dayofweek_expression = split(cron, " ")

    expressions = [
        matchPrimitives(seconds_expression, time, second),
        matchPrimitives(minute_expression, time, minute),
        matchPrimitives(hour_expression, time, hour),
        matchPrimitives(dayofmonth_expression, time, dayofmonth),
        matchPrimitives(month_expression, time, month),
        matchPrimitives(dayofweek_expression, time, dayofweek)
    ]

    should_execute = all(expressions)
    println(time)

    if should_execute
        println("boom")
    end

end

everysecond(run)


end 