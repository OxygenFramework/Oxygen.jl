module MCPToolsDemo

using Oxygen
using JSON3
using Dates

@tool "Get current time in specified format" Dict(:format => "DateTime format string") function get_time(format::String)
    return JSON3.write(Dict(
        "time" => Dates.format(now(), format)
    ))
end

@enum SortOrder relevance = 1 date = 2 name = 3

@tool "Search with filters" Dict(
    :query => "Search query",
    :tags => "Filter tags",
    :sort => "Sort order"
    ) function search(query::String, tags::Vector{String}=String[], sort::SortOrder=relevance)
    return "Searching '$query' with $(length(tags)) tags, sorted by $sort"
end

serve(mcp_server_name="tools-server")

end
