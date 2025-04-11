module BonitoTests
using Base64
using HTTP
using Test
using Bonito
using Oxygen; @oxidise
import Oxygen: text, html
using ..Constants

@testset "Bonito Utils tests" begin 

    app = App() do
        return DOM.div(DOM.h1("hello world"), js"""console.log('hello world')""")
    end

    response = html(app)
    @test response isa HTTP.Response
    @test response.status == 200
    @test HTTP.header(response, "Content-Type") == "text/html"
    @test parse(Int, HTTP.header(response, "Content-Length")) >= 0
end

@testset "Bonito server tests" begin

    get("/") do 
        text("hello world")
    end

    get("/html") do 
        html("hello world")
    end

    get("/plot/html") do 
        app = App() do
            return DOM.div(DOM.h1("hello world"))
        end
        html(app)
    end

    serve(host=HOST, port=PORT, async=true, show_banner=false, access_log=nothing)

    # Test overloaded text() function
    r = HTTP.get("$localhost/")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/plain; charset=utf-8"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0

    # Test overloaded html function
    r = HTTP.get("$localhost/html")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/html; charset=utf-8"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0

    # Test for /plot/html endpoint
    r = HTTP.get("$localhost/plot/html")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/html"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0
    terminate()
end

@testset "Bonito websocket connection tests" begin
    get("/connection") do
        app = App() do
            counter = Observable(0)
            button = Bonito.Button("increment")
            on(button.value) do click::Bool
                counter[] += 1
            end
            DOM.div(DOM.h2(counter), button)
        end
        html(app)
    end

    setup_bonito_connection(; setup_all=true)

    serve(host=HOST, port=PORT, async=true, show_banner=false, access_log=nothing)

    # Test overloaded text() function
    r = HTTP.get("$localhost/connection")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/html"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0

    scripts_regex = r"src=\"data:application/javascript;base64,([^\"]+)\""
    base64_scripts = [match[1] for match in eachmatch(scripts_regex, String(r.body))]
    @test length(base64_scripts) >= 1
    sort!(base64_scripts; by=length)

    ws_regex = r"WS.setup_connection\(([^)]+)\)"s

    ws_args = nothing
    for script in base64_scripts
        script = String(base64decode(script))
        ws_match = match(ws_regex, script)
        if ws_match != nothing
            ws_args = ws_match[1]
            ws_args = replace(ws_args, r"[\"'{}\s]+" => "")
            ws_args = split(ws_args, ",")
            new_ws_args = Dict()
            for arg in ws_args
                bits = split(arg, ":"; limit=2)
                new_ws_args[String(strip(bits[1]))] = String(strip(bits[2]))
            end
            ws_args = new_ws_args
            break
        end
    end
    @test ws_args != nothing
    @test "proxy_url" in keys(ws_args)
    @test "session_id" in keys(ws_args)
    @test ws_args["proxy_url"] == "$localhost/bonito-websocket/"
    session_id = ws_args["session_id"]

    websocket_url = "$localhost/bonito-websocket/$session_id"
    websocket_url = replace(websocket_url, "http" => "ws")
    saved_ws = nothing
    WebSockets.open(websocket_url) do ws
        saved_ws = ws
    end
    @test saved_ws !== nothing
    @test saved_ws.response.status == 101
    @test WebSockets.isclosed(saved_ws)

    terminate()
end

end
