module SSEDemo
using HTTP

include("../src/Oxygen.jl")
using .Oxygen

@get "/" function()
    html("""
    <html>
        <head>
            <meta charset="UTF-8">
            <title>Server-sent events demo</title>
        </head>
        <body>
            <h3>Fetched items:</h3>
            <ul id="list"></ul>
        </body>
        <script>
            const evtSource = new EventSource("http://127.0.0.1:8080/api/events")
            evtSource.onmessage = async function (event) {
                const newElement = document.createElement("li");
                const eventList = document.getElementById("list");
                const r = await fetch("http://127.0.0.1:8080/api/getItems")
                if (r.ok) {
                    const body = await r.json()
                    newElement.textContent = body;
                    eventList.appendChild(newElement);
                }
            }
            evtSource.addEventListener("ping", function(event) {
                console.log('ping:', event.data)
            });
        </script>
        </html>
    """)
end

@get "/text" function()
    text("Hello, world!")
end

@get "/api/getItems" function(req)
    json(rand(2))
end

@sse "/api/events" function(stream::HTTP.Stream)
    HTTP.setheader(stream, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(stream, "Access-Control-Allow-Methods" => "GET")
    HTTP.setheader(stream, "Content-Type" => "text/event-stream")
    HTTP.setheader(stream, "Cache-Control" => "no-cache")
    while true
        write(stream, "event: ping\ndata: $(round(Int, time()))\n\n")
        write(stream, "data: $(rand())\n\n")
        sleep(1)
    end
    return nothing
end

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS"
]

# https://juliaweb.github.io/HTTP.jl/stable/examples/#Cors-Server
function CorsMiddleware(handler)
    return function(req::HTTP.Request)
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, CORS_HEADERS)
        else 
            response = handler(req)
            for (k,v) in CORS_HEADERS
                HTTP.setheader(response, k => v)
            end
            response
        end
    end
end


serve(middleware=[CorsMiddleware], access_log=nothing)

end