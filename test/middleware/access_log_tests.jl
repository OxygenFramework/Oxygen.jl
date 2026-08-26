module AccessLogMiddlewareTests

module DefaultFormatTests

    using Test
    using Logging
    using HTTP
    using Oxygen; @oxidize
    using ...Constants

    @get "/hello" function()
        return text("world")
    end

    @get "/custom-header" function()
        return text("ok", headers=["X-Foo" => "bar"])
    end

    test_logger = Test.TestLogger()
    serve(middleware=[AccessLog()], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false)

    # note: request handlers run in separate server tasks, so we must swap
    # the global logger (task-local loggers are not visible to them)
    function capture(f)
        previous = global_logger(test_logger)
        try
            return f()
        finally
            global_logger(previous)
        end
    end

    @testset "AccessLog default (common log format)" begin
        capture() do
            r = HTTP.get("$localhost/hello"; headers=Dict("User-Agent" => "test-agent"))
            @test r.status == 200
            r = HTTP.get("$localhost/custom-header")
            @test r.status == 200
        end

        records = test_logger.logs
        @test length(records) == 2
        for record in records
            @test record.level == Logging.Info
            @test record.group == :access
        end
        # 127.0.0.1 - - [timestamp] "GET /hello HTTP/1.1" 200 5
        @test occursin(r"^127\.0\.0\.1 - - \[.*\] \"GET /hello HTTP/1\.1\" 200 5$", records[1].message)
        @test occursin(r"^127\.0\.0\.1 - - \[.*\] \"GET /custom-header HTTP/1\.1\" 200 2$", records[2].message)
    end

    terminate()

end

module CustomFormatTests

    using Test
    using Logging
    using HTTP
    using Oxygen; @oxidize
    using ...Constants

    @get "/hello" function()
        return text("world")
    end

    custom_format = logfmt"$remote_addr:$remote_port \"$request\" $status $body_bytes_sent $sent_http_content_type"

    test_logger = Test.TestLogger()
    serve(middleware=[AccessLog(format=custom_format)], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false)

    function capture(f)
        previous = global_logger(test_logger)
        try
            return f()
        finally
            global_logger(previous)
        end
    end

    @testset "AccessLog custom logfmt format" begin
        capture() do
            r = HTTP.get("$localhost/hello")
            @test r.status == 200
        end

        records = test_logger.logs
        @test length(records) == 1
        @test records[1].group == :access
        # 127.0.0.1:port "GET /hello HTTP/1.1" 200 5 text/plain
        @test occursin(r"^127\.0\.0\.1:\d+ \"GET /hello HTTP/1\.1\" 200 5 text/plain", records[1].message)
    end

    terminate()

end

module CombinedFormatTests

    using Test
    using Logging
    using HTTP
    using Oxygen; @oxidize
    using ...Constants

    @get "/hello" function()
        return text("world")
    end

    test_logger = Test.TestLogger()
    serve(middleware=[AccessLog(format=combined_logfmt)], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false)

    function capture(f)
        previous = global_logger(test_logger)
        try
            return f()
        finally
            global_logger(previous)
        end
    end

    @testset "AccessLog combined log format" begin
        capture() do
            r = HTTP.get("$localhost/hello"; headers=Dict("Referer" => "http://example.com", "User-Agent" => "test-agent"))
            @test r.status == 200
        end

        records = test_logger.logs
        @test length(records) == 1
        @test records[1].group == :access
        @test occursin(r"^127\.0\.0\.1 - - \[.*\] \"GET /hello HTTP/1\.1\" 200 5 \"http://example\.com\" \"test-agent\"$", records[1].message)
    end

    terminate()

end

module UnknownVariableTests

    using Test
    using Logging
    using Oxygen; @oxidize
    using ...Constants

    @testset "logfmt unknown variable errors at definition time" begin
        err = try
            eval(:(Oxygen.@logfmt_str "\$bogus_variable"))
            nothing
        catch e
            e
        end
        @test err !== nothing
        @test occursin("unknown variable", sprint(showerror, err))
    end

end

end