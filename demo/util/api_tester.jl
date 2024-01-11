module ApiTester

using HTTP
using Distributions
using Random

function random_requester(urls::Array{String,1}, req_range::Tuple{Int, Int})
    # Ensure the range is valid
    if req_range[1] > req_range[2] || req_range[1] < 0
        error("Invalid range of requests per second.")
    end

    # Calculate the time interval range in seconds (as floating point numbers)
    interval_range = (1.0 / req_range[2], 1.0 / req_range[1])

    while true
        # Choose a random URL from the list
        url = rand(urls)

        # Generate a random request interval from the specified range
        interval = rand(Uniform(interval_range[1], interval_range[2]))

        # Send the HTTP request
        try
            response = HTTP.get(url)
            println("Requested $(url): Status $(response.status)")
        catch e
            println("Failed to request $(url): $(e)")
        end

        # Wait for the random interval before sending the next request
        sleep(interval)
    end
end

# Example usage:
urls = [
    "http://localhost:8080/data",
    "http://localhost:8080/data", 
    "http://localhost:8080/data",  
    "http://localhost:8080/data",
    "http://localhost:8080/data", 
    "http://localhost:8080/data", 
    "http://localhost:8080/data",
    "http://localhost:8080/data", 
    "http://localhost:8080/data",

    "http://localhost:8080/random/lg", 
    "http://localhost:8080/random/lg", 
    "http://localhost:8080/random/lg", 

    "http://localhost:8080/random/md", 
    "http://localhost:8080/random/md", 
    "http://localhost:8080/random/md", 
    "http://localhost:8080/random/md", 

    "http://localhost:8080/random/sm", 
    "http://localhost:8080/random/sm", 
    "http://localhost:8080/random/sm", 
    "http://localhost:8080/random/sm", 
    "http://localhost:8080/random/sm", 
    "http://localhost:8080/random/sm", 
    
    "http://localhost:8080/fake",
    "http://localhost:8080/error",
    "http://localhost:8080/nothing",
]
random_requester(urls, (1, 8))  # Randomly hit endpoints between 1 and 5 requests per second

end