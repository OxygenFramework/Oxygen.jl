module CronTests 
using Test
using HTTP
using JSON3
using StructTypes
using Sockets
using Dates 

using Oxygen

using Oxygen.Core.Cron: iscronmatch, isweekday, lastweekdayofmonth, 
            next, sleep_until, lastweekday, nthweekdayofmonth, 
            matchexpression

const PORT = 7070 # 8080 is a very common port and could already be in use

@testset "Cron Module Tests" begin

    @testset "methods" begin 
        @test lastweekday(DateTime(2022,1,1,0,0,0)) == DateTime(2021,12,31,0,0,0)

        @test lastweekday(DateTime(2022,1,3,0,0,0)) != DateTime(2022,1,8,0,0,0)
        @test lastweekday(DateTime(2022,1,3,0,0,0)) == DateTime(2022,1,7,0,0,0)
        @test lastweekday(DateTime(2022,1,3,0,0,0)) != DateTime(2022,1,6,0,0,0)

    end

    @testset "lastweekdayofmonth" begin
        @test lastweekdayofmonth(DateTime(2022,1,1,0,0,0)) == DateTime(2022,1,31,0,0,0)
    end


    @testset "nthweekdayofmonth" begin
        @test_throws ErrorException nthweekdayofmonth(DateTime(2022,1,1,0,0,0), -1)
        @test_throws ErrorException nthweekdayofmonth(DateTime(2022,1,1,0,0,0), 50)
    end

    @testset "sleep_until" begin
        @test sleep_until(now(), DateTime(2020,1,1,0,0,0)) == 0
    end


    @testset "lastweekdayofmonth function tests" begin
        # Test when last day of the month is a Friday
        time = DateTime(2023, 9, 20)
        @test lastweekdayofmonth(time) == DateTime(2023, 9, 29)

        # Test when last day of the month is a Saturday
        time = DateTime(2023, 4, 15)
        @test lastweekdayofmonth(time) == DateTime(2023, 4, 28)

        # Test when last day of the month is a Sunday
        time = DateTime(2023, 10, 10)
        @test lastweekdayofmonth(time) == DateTime(2023, 10, 31) # Corrected date

        # Test when last day of the month is a weekday (Monday-Thursday)
        time = DateTime(2023, 11, 15)
        @test lastweekdayofmonth(time) == DateTime(2023, 11, 30)

        # Test with a leap year (February)
        time = DateTime(2024, 2, 20)
        @test lastweekdayofmonth(time) == DateTime(2024, 2, 29)

        # Test with a non-leap year (February)
        time = DateTime(2023, 2, 20)
        @test lastweekdayofmonth(time) == DateTime(2023, 2, 28) # Corrected date
    end




    @testset "next function tests" begin
        # Test all fields with asterisk (wildcard)
        start_time = DateTime(2023, 4, 3, 12, 30, 45)
        @test next("* * * * * *", start_time) == start_time + Second(1)

        # Test matching specific fields
        start_time = DateTime(2023, 1, 1, 0, 0, 0)
        @test next("30 15 10 5 2 *", start_time) == DateTime(2023, 2, 5, 10, 15, 30)

        # Test edge case: leap year
        start_time = DateTime(2020, 1, 1, 0, 0, 0)
        @test next("0 0 0 29 2 *", start_time) == DateTime(2020, 2, 29, 0, 0, 0)

        # Test edge case: end of the month
        start_time = DateTime(2023, 12, 30, 23, 59, 59)
        @test next("0 0 0 31 12 *", start_time) == DateTime(2023, 12, 31, 0, 0, 0)

        # Test edge case: end of the year
        start_time = DateTime(2022, 12, 31, 23, 59, 59)
        @test next("0 0 0 1 1 *", start_time) == DateTime(2023, 1, 1, 0, 0, 0)

        # Test day of the week
        start_time = DateTime(2023, 4, 3, 11, 59, 59)
        @test next("0 0 12 * * 1", start_time) == DateTime(2023, 4, 3, 12, 0, 0)

        # Test ranges and increments
        start_time = DateTime(2023, 4, 3, 10, 35, 0)
        @test next("0 */10 8-18 * * *", start_time) == DateTime(2023, 4, 3, 10, 40, 0)

        # Test wrapping around years
        start_time = DateTime(2023, 12, 31, 23, 59, 59)
        @test next("0 0 0 1 1 *", start_time) == DateTime(2024, 1, 1, 0, 0, 0)

        # Test wrapping around months
        start_time = DateTime(2023, 12, 31, 23, 59, 59)
        @test next("0 0 0 1 * *", start_time) == DateTime(2024, 1, 1, 0, 0, 0)

        # Test wrapping around days
        start_time = DateTime(2023, 4, 3, 23, 59, 59)
        @test next("0 0 * * * *", start_time) == DateTime(2023, 4, 4, 0, 0, 0)

        # Test wrapping around hours
        start_time = DateTime(2023, 4, 3, 23, 59, 59)
        @test next("0 * * * * *", start_time) == DateTime(2023, 4, 4, 0, 0, 0)

        # Test wrapping around minutes
        start_time = DateTime(2023, 4, 3, 23, 59, 59)
        @test next("* * * * * *", start_time) == DateTime(2023, 4, 4, 0, 0, 0)

        # Test case with only seconds field
        start_time = DateTime(2023, 4, 3, 12, 30, 29)
        @test next("30 * * * * *", start_time) == DateTime(2023, 4, 3, 12, 30, 30)
    end

    using Test
    @testset "matchexpression function tests" begin
        time = DateTime(2023, 4, 3, 23, 59, 59)
        minute = Dates.minute
        second = Dates.second

        @test matchexpression(SubString("*"), time, minute, 59) == true
        @test matchexpression(SubString("59"), time, minute, 59) == true
        @test matchexpression(SubString("15"), time, minute, 59) == false
        @test matchexpression(SubString("45,59"), time, second, 59) == true
        @test matchexpression(SubString("15,30"), time, second, 59) == false
        @test matchexpression(SubString("50-59"), time, second, 59) == true
        @test matchexpression(SubString("10-40"), time, second, 59) == false
        @test matchexpression(SubString("59-*"), time, minute, 59) == true
        @test matchexpression(SubString("*-58"), time, minute, 59) == false
        @test matchexpression(SubString("*/10"), time, minute, 59) == false
        @test matchexpression(SubString("25/5"), time, minute, 59) == false
    end



        
    @testset "seconds tests" begin 
        # check exact second 
        @test iscronmatch("5/*", DateTime(2022,1,1,1,0,5)) == true
        @test iscronmatch("7/*", DateTime(2022,1,1,1,0,7)) == true

        # check between ranges
        @test iscronmatch("5-*", DateTime(2022,1,1,1,0,7)) == true
        @test iscronmatch("*-10", DateTime(2022,1,1,1,0,7)) == true
    end

    @testset "static matches" begin

        # Exact second match
        @test iscronmatch("0", DateTime(2022,1,1,1,0,0)) == true
        @test iscronmatch("1", DateTime(2022,1,1,1,0,1)) == true
        @test iscronmatch("5", DateTime(2022,1,1,1,0,5)) == true
        @test iscronmatch("7", DateTime(2022,1,1,1,0,7)) == true
        @test iscronmatch("39", DateTime(2022,1,1,1,0,39)) == true
        @test iscronmatch("59", DateTime(2022,1,1,1,0,59)) == true

        # Exact minute match
        @test iscronmatch("* 0", DateTime(2022,1,1,1,0,0)) == true
        @test iscronmatch("* 1", DateTime(2022,1,1,1,1,0)) == true
        @test iscronmatch("* 5", DateTime(2022,1,1,1,5,0)) == true
        @test iscronmatch("* 7", DateTime(2022,1,1,1,7,0)) == true
        @test iscronmatch("* 39", DateTime(2022,1,1,1,39,0)) == true
        @test iscronmatch("* 59", DateTime(2022,1,1,1,59,0)) == true

        # Exact hour match
        @test iscronmatch("* * 0", DateTime(2022,1,1,0,0,0)) == true
        @test iscronmatch("* * 1", DateTime(2022,1,1,1,0,0)) == true
        @test iscronmatch("* * 5", DateTime(2022,1,1,5,0,0)) == true
        @test iscronmatch("* * 12", DateTime(2022,1,1,12,0,0)) == true
        @test iscronmatch("* * 20", DateTime(2022,1,1,20,0,0)) == true
        @test iscronmatch("* * 23", DateTime(2022,1,1,23,0,0)) == true

        # Exact day match
        @test iscronmatch("* * * 1", DateTime(2022,1,1,1,0,0)) == true
        @test iscronmatch("* * * 5", DateTime(2022,1,5,1,0,0)) == true
        @test iscronmatch("* * * 12", DateTime(2022,1,12,1,0,0)) == true
        @test iscronmatch("* * * 20", DateTime(2022,1,20,1,0,0)) == true
        @test iscronmatch("* * * 31", DateTime(2022,1,31,1,0,0)) == true

        # Exact month match
        @test iscronmatch("* * * * 1", DateTime(2022,1,1,0,0,0)) == true
        @test iscronmatch("* * * * 4", DateTime(2022,4,1,1,0,0)) == true
        @test iscronmatch("* * * * 5", DateTime(2022,5,1,1,0,0)) == true
        @test iscronmatch("* * * * 9", DateTime(2022,9,1,1,0,0)) == true
        @test iscronmatch("* * * * 12", DateTime(2022,12,1,1,0,0)) == true

        # Exact day of week match
        @test iscronmatch("* * * * * MON", DateTime(2022,1,3,0,0,0)) == true
        @test iscronmatch("* * * * * MON", DateTime(2022,1,10,0,0,0)) == true
        @test iscronmatch("* * * * * MON", DateTime(2022,1,17,0,0,0)) == true

        @test iscronmatch("* * * * * TUE", DateTime(2022,1,4,0,0,0)) == true
        @test iscronmatch("* * * * * TUE", DateTime(2022,1,11,0,0,0)) == true
        @test iscronmatch("* * * * * TUE", DateTime(2022,1,18,0,0,0)) == true

        @test iscronmatch("* * * * * WED", DateTime(2022,1,5,0,0,0)) == true
        @test iscronmatch("* * * * * WED", DateTime(2022,1,12,0,0,0)) == true
        @test iscronmatch("* * * * * WED", DateTime(2022,1,19,0,0,0)) == true

        @test iscronmatch("* * * * * THU", DateTime(2022,1,6,0,0,0)) == true
        @test iscronmatch("* * * * * THU", DateTime(2022,1,13,0,0,0)) == true
        @test iscronmatch("* * * * * THU", DateTime(2022,1,20,0,0,0)) == true

        @test iscronmatch("* * * * * FRI", DateTime(2022,1,7,0,0,0)) == true
        @test iscronmatch("* * * * * FRI", DateTime(2022,1,14,0,0,0)) == true
        @test iscronmatch("* * * * * FRI", DateTime(2022,1,21,0,0,0)) == true

        @test iscronmatch("* * * * * SAT", DateTime(2022,1,8,0,0,0)) == true
        @test iscronmatch("* * * * * SAT", DateTime(2022,1,15,0,0,0)) == true
        @test iscronmatch("* * * * * SAT", DateTime(2022,1,22,0,0,0)) == true

        @test iscronmatch("* * * * * SUN", DateTime(2022,1,2,0,0,0)) == true
        @test iscronmatch("* * * * * SUN", DateTime(2022,1,9,0,0,0)) == true
        @test iscronmatch("* * * * * SUN", DateTime(2022,1,16,0,0,0)) == true

    end

    # # More specific test cases
    # # "0 0 * * * *" = the top of every hour of every day.
    # # "*/10 * * * * *" = every ten seconds.
    # # "0 0 8-10 * * *" = 8, 9 and 10 o'clock of every day.
    # # "0 0 6,19 * * *" = 6:00 AM and 7:00 PM every day.
    # # "0 0/30 8-10 * * *" = 8:00, 8:30, 9:00, 9:30, 10:00 and 10:30 every day.
    # # "0 0 9-17 * * MON-FRI" = on the hour nine-to-five weekdays
    # # "0 0 0 25 12 ?" = every Christmas Day at midnight
    # # "0 0 0 L * *" = last day of the month at midnight
    # # "0 0 0 L-3 * *" = third-to-last day of the month at midnight
    # # "0 0 0 1W * *" = first weekday of the month at midnight
    # # "0 0 0 LW * *" = last weekday of the month at midnight
    # # "0 0 0 * * 5L" = last Friday of the month at midnight
    # # "0 0 0 * * THUL" = last Thursday of the month at midnight
    # # "0 0 0 ? * 5#2" = the second Friday in the month at midnight
    # # "0 0 0 ? * MON#1" = the first Monday in the month at midnight


    @testset "the top of every hour of every day" begin
        for hour in 0:23
            @test iscronmatch("0 0 * * * *", DateTime(2022,1,1,hour,0,0)) == true
        end
    end

    @testset "the 16th minute of every hour of every day" begin
        for hour in 0:23
            @test iscronmatch("0 16 * * * *", DateTime(2022,1,1,hour,16,0)) == true
        end
    end


    @testset "8, 9 and 10 o'clock of every day." begin
        for hour in 0:23
            @test iscronmatch("0 0 8-10 * * *", DateTime(2022,1,1,hour,0,0)) == (hour >= 8 && hour <= 10)
        end
    end


    @testset "every 10 seconds" begin
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,0)) == true
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,10)) == true
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,20)) == true
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,30)) == true
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,40)) == true
        @test iscronmatch("*/10 * * * * *", DateTime(2022,1,9,1,0,50)) == true
    end

    @testset "every 7 seconds" begin
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,0)) == false
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,7)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,14)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,21)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,28)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,35)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,42)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,49)) == true
        @test iscronmatch("*/7 * * * * *", DateTime(2022,1,9,1,0,56)) == true
    end

    @testset "every 15 seconds" begin
        @test iscronmatch("*/15 * * * * *", DateTime(2022,1,9,1,0,0)) == true
        @test iscronmatch("*/15 * * * * *", DateTime(2022,1,9,1,0,15)) == true
        @test iscronmatch("*/15 * * * * *", DateTime(2022,1,9,1,0,30)) == true
        @test iscronmatch("*/15 * * * * *", DateTime(2022,1,9,1,0,45)) == true
    end


    @testset "6:00 AM and 7:00 PM every day" begin 
        for day in 1:20
            for hour in 0:23
                @test iscronmatch("0 0 6,19 * * *", DateTime(2022,1,day,hour,0,0)) == (hour == 6 || hour == 19)
            end
        end
    end


    @testset "8:00, 8:30, 9:00, 9:30, 10:00 and 10:30 every day" begin 
        for day in 1:20
            for hour in 0:23
                @test iscronmatch("0 0/30 8-10 * * *", DateTime(2022,1,day,hour,30,0)) == (hour >= 8 && hour <= 10)
                @test iscronmatch("0 0/30 8-10 * * *", DateTime(2022,1,day,hour,0,0)) == (hour >= 8 && hour <= 10)
            end
        end
    end


    @testset "on the hour nine-to-five weekdays" begin 
        for day in 1:20
            if isweekday(DateTime(2022,1,day,0,0,0))
                for hour in 0:23
                    @test iscronmatch("0 0 9-17 * * MON-FRI", DateTime(2022,1,day,hour,0,0)) == (hour >= 9 && hour <= 17)
                end
            end
        end
    end


    @testset "every Christmas Day at midnight" begin 
        for month in 1:12
            for hour in 0:23
                @test iscronmatch("0 0 0 25 12 ?", DateTime(2022,month,25,hour,0,0)) == (month == 12 && hour == 0)
            end
        end
    end

    @testset "last day of the month at midnight" begin 
        for month in 1:12
            num_days = daysinmonth(2022, month)
            for day in 1:num_days
                for hour in 0:23
                    @test iscronmatch("0 0 0 L * *", DateTime(2022,month,day,hour,0,0)) == (day == num_days && hour == 0)
                end
            end
        end
    end


    @testset "third-to-last day of the month at midnight" begin 
        for month in 1:12
            num_days = daysinmonth(2022, month)
            for day in 1:num_days
                for hour in 0:23
                    @test iscronmatch("0 0 0 L-3 * *", DateTime(2022,month,day,hour,0,0)) == (day == (num_days-3) && hour == 0)
                end
            end
        end
    end

    @testset "first weekday of the month at midnight" begin

        @test iscronmatch("0 0 0 1W * *", DateTime(2022, 1, 3, 0, 0, 0)) 
        @test iscronmatch("0 0 0 9W * *", DateTime(2022, 1, 10, 0, 0, 0)) 
        @test iscronmatch("0 0 0 13W * *", DateTime(2022, 1, 13, 0, 0, 0)) 
        @test iscronmatch("0 0 0 15W * *", DateTime(2022, 1, 14, 0, 0, 0)) 
        @test iscronmatch("0 0 0 22W * *", DateTime(2022, 1, 21, 0, 0, 0)) 
        @test iscronmatch("0 0 0 31W * *", DateTime(2022, 1, 31, 0, 0, 0)) 

    end

    @testset "last weekday of the month at midnight" begin
        @test iscronmatch("0 0 0 LW * *", DateTime(2022, 1, 28, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 LW * *", DateTime(2022, 1, 29, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 LW * *", DateTime(2022, 1, 30, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 LW * *", DateTime(2022, 1, 30, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 LW * *", DateTime(2022, 1, 31, 0, 0, 0)) 
    end

    @testset "last Friday of the month at midnight" begin
        @test iscronmatch("0 0 0 * * 5L", DateTime(2022, 1, 28, 0, 0, 0))
        @test iscronmatch("0 0 0 * * 5L", DateTime(2022, 1, 29, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 * * 5L", DateTime(2022, 1, 29, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 * * 5L", DateTime(2022, 2, 25, 0, 0, 0))
    end


    @testset "last Thursday of the month at midnight" begin
        @test iscronmatch("0 0 0 * * THUL", DateTime(2022, 1, 26, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 * * THUL", DateTime(2022, 1, 27, 0, 0, 0))
        @test iscronmatch("0 0 0 * * THUL", DateTime(2022, 1, 28, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 * * THUL", DateTime(2022, 2, 3, 0, 0, 0)) == false
    end


    @testset "the second Friday in the month at midnight" begin
        @test iscronmatch("0 0 0 ? * 5#2", DateTime(2022, 1, 14, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * 5#2", DateTime(2022, 2, 11, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * 5#2", DateTime(2022, 3, 11, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * 5#2", DateTime(2022, 4, 8, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * 5#2", DateTime(2022, 5, 13, 0, 0, 0))
    end


    @testset "the first Monday in the month at midnight" begin
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 1, 2, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 1, 3, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 1, 4, 0, 0, 0)) == false

        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 2, 6, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 2, 7, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 2, 8, 0, 0, 0)) == false

        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 3, 6, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 3, 7, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 3, 8, 0, 0, 0)) == false

        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 4, 3, 0, 0, 0)) == false
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 4, 4, 0, 0, 0))
        @test iscronmatch("0 0 0 ? * MON#1", DateTime(2022, 4, 5, 0, 0, 0)) == false
    end


    localhost = "http://127.0.0.1:$PORT"

    crondata = Dict("api_value" => 0)

    @get router("/cron-increment", cron="*") function(req)
        crondata["api_value"] = crondata["api_value"] + 1
        return crondata["api_value"]
    end

    @get "/get-cron-increment" function()
        return crondata["api_value"]
    end

    server = serve(async=true, port=PORT, show_banner=false)
    sleep(3)

    internalrequest(HTTP.Request("GET", "/cron-increment"))
    internalrequest(HTTP.Request("GET", "/cron-increment"))

    @testset "Testing CRON API access" begin
        r = internalrequest(HTTP.Request("GET", "/get-cron-increment"))
        @test r.status == 200
        @test parse(Int64, text(r)) > 0
    end

    close(server) 

    end

end
