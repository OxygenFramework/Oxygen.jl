module StreamingChunksDemo

using JSON
using Dates
using HTTP
using JSON
using Oxygen

function chunks(data::Any, nchunks::Int)
    return chunks(JSON.json(data), nchunks)
end

function chunks(data::String, nchunks::Int)
    # Convert the data to binary
    binarydata = Vector{UInt8}(data)
    data_size = sizeof(binarydata) 

    # Calculate chunk size
    chunk_size = ceil(Int, data_size / nchunks)

    # return a generator for the chunks
    return (binarydata[i:min(i + chunk_size - 1, end)] for i in 1:chunk_size:data_size)
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

    # Write each chunk to the stream
    for chunk in chunks(data, nchunks)
        write(stream, chunk)
    end

    # Close the stream to end the HTTP response properly
    closewrite(stream)
end


# Chunk Text
@stream "/api/chunked/text" function(stream::HTTP.Stream)
    # Set headers
    HTTP.setheader(stream, "Content-Type" => "text/plain")
    HTTP.setheader(stream, "Transfer-Encoding" => "chunked")

    # Start writing (if you need to send headers before the body)
    startwrite(stream)

    data = ["a", "b", "c"]
    for chunk in data
        write(stream, chunk)
    end

    # Close the stream to end the HTTP response properly
    closewrite(stream)
end


serve()

end