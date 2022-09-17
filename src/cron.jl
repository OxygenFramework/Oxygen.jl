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



# https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/support/CronExpression.html
# range expressions: 8-10
# list expressions: 6,19
# https://crontab.cronhub.io/

function matchPrimitives(input::SubString, time::DateTime, converter) :: Bool
    current = converter(time)
    numericvalue = tryparse(Int8, input)

    # Every Second
    if input == "*"
        return true 
    # At X seconds past the minute
    elseif numericvalue !== nothing
        return numericvalue == current

    elseif contains(input, ",")
        lowerbound, upperbound = split(input, ",")
        return current == parse(Int8, lowerbound) || current === parse(Int8, upperbound)

    elseif contains(input, "-")
        lowerbound, upperbound = split(input, "-")
        if lowerbound == "*"
            return current <= parse(Int8, upperbound)
        elseif upperbound == "*"
            return current >= parse(Int8, lowerbound)
        else 
            return current >= parse(Int8, lowerbound) && current <= parse(Int8, upperbound)
        end
        
    elseif contains(input, "/")
        numerator, denominator = split(input, "/")
        # Every second, starting at Y seconds past the minute
        if denominator == "*"
            numerator = parse(Int8, numerator)
            return current >= numerator
        elseif numerator == "*"
            # Every X seconds
            denominator = parse(Int8, denominator)
            return current % denominator == 0
        else
            # Every X seconds, starting at Y seconds past the minute
            numerator = parse(Int8, numerator)
            denominator = parse(Int8, denominator)
            return current % denominator == 0 && current >= numerator
        end
    else 
        return false
    end
end

cron = "* 34-35 23 * * *" # every 10 seconds

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