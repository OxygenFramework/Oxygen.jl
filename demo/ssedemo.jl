module SSEDemo
using JSON3
using Dates
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



"""
    server_event(data::String; event::Union{String, Nothing} = nothing, id::Union{String, Nothing} = nothing)

Create a properly formatted Server-Sent Event (SSE) string.

# Arguments
- `data`: The data to send. This should be a string. Newline characters in the data will be replaced with separate "data:" lines.
- `event`: (optional) The type of event to send. If not provided, no event type will be sent. Should not contain newline characters.
- `id`: (optional) The ID of the event. If not provided, no ID will be sent. Should not contain newline characters.

# Notes
This function follows the Server-Sent Events (SSE) specification for sending events to the client.
"""
function server_event(
    data    :: String; 
    event   :: Union{String, Nothing} = nothing, 
    id      :: Union{String, Nothing} = nothing) :: String

    has_id = !isnothing(id) 
    has_event = !isnothing(event) 

    # check if event or id contain newline characters
    if has_id && contains(id, '\n')
        throw(ArgumentError("Event ID cannot contain newline characters: $id"))
    end

    if has_event && contains(event, '\n')
        throw(ArgumentError("Event type cannot contain newline characters: $event"))
    end

    io = IOBuffer()
    
    # Make sure we don't send any newlines in the data proptery
    for line in split(data, '\n')
        write(io, "data: $line\n")
    end
    
    # Optional properties
    has_id     && write(io, "id: $id\n")
    has_event  && write(io, "event: $event\n")

    # Terminate the event, by marking it with a doubule newline
    write(io, "\n")

    # return the content of the buffer as a string
    return String(take!(io))
end

nchunks = 5
data = Dict()

# Add new properties with large arrays of values
for i in 1:100
    data["property$i"] = rand(1000) # Each property will have an array of 1000 random numbers
end

@stream "/api/chunked/json" function(stream::HTTP.Stream)

    # Set headers
    HTTP.setheader(stream, "Content-Type" => "application/json")
    HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
       
    # Start writing (if you need to send headers before the body)
    startwrite(stream)

    # convert the entire data strcture to binary
    binarydata = Vector{UInt8}(JSON3.write(data))

    # Calculate chunk size
    chunk_size = ceil(Int, sizeof(binarydata) / nchunks)

    # Split r.body into 4 chunks
    chunks = [binarydata[i:min(i+chunk_size-1, end)] for i in 1:chunk_size:sizeof(binarydata)]

    # Write each chunk to the stream
    for chunk in chunks
        write(stream, chunk)
    end

    # Close the stream to end the HTTP response properly
    closewrite(stream)
end


# Chunk Text
@stream "/api/chunked/text" function(stream::HTTP.Stream)

    # Start writing (if you need to send headers before the body)
   startwrite(stream)
   
    # Write data in chunks
    chunks = ["This is the first chunk of data.\n", "Here's another chunk of data.\n", "Final chunk.\n"]
    for chunk in chunks
        # The write function takes care of chunking automatically if required
        write(stream, chunk)
    end

    # Close the stream to end the HTTP response properly
    closewrite(stream)
end

@stream "/api/events" function(stream::HTTP.Stream)
    HTTP.setheader(stream, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(stream, "Access-Control-Allow-Methods" => "GET")
    HTTP.setheader(stream, "Content-Type" => "text/event-stream")
    HTTP.setheader(stream, "Cache-Control" => "no-cache")

    while true
        message = "The time is: $(now())"

        write(stream, server_event(message))
        write(stream, server_event(message; event="ping"))

        sleep(1)
    end
    return nothing
end

serve()

end