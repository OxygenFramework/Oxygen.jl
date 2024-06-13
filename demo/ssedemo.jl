module SSEDemo

using JSON3
using Dates
using HTTP
using Oxygen

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
                newElement.textContent = event.data;
                eventList.appendChild(newElement);
            }
            evtSource.addEventListener("ping", function(event) {
                console.log('ping:', event.data)
            });
        </script>
        </html>
    """)
end


@stream "/api/events" function(stream::HTTP.Stream)
    HTTP.setheader(stream, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(stream, "Access-Control-Allow-Methods" => "GET")
    HTTP.setheader(stream, "Content-Type" => "text/event-stream")
    HTTP.setheader(stream, "Cache-Control" => "no-cache")

    
    while true
        message = "The time is: $(now())"

        write(stream, format_sse_message(message))
        write(stream, format_sse_message(message; event="ping"))

        sleep(1)
    end
    return nothing
end

serve()

end