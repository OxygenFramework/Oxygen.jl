module MimeTypes 

using HTTP

export mimetype

# Maps file exstenion => mime type
global const mimetypes = Ref{Dict{String,String}}(Dict())

"""
return the path to the mime types file 
"""
function datapath()
    abspath(joinpath(@__DIR__, "..", "data", "mime.types"))
end

"""
Parse each line in the mime.types file
"""
function parsefile(filepath)
    local data = Dict{String,String}()
    for line in eachline(filepath)
        if !isnothing(line) && !isempty(line) && !startswith(line, "#")
            mimetype, exstenions... = split(line)
            for ext in exstenions 
                data[ext] = mimetype
            end
        end
    end
    return data
end

"""
Takes a filename and returns the corresponding mime-type
"""
function mimetype(filename::String)
    if isnothing(filename) || isempty(filename) || !contains(filename, ".")
        return "text/plain"
    end
    exstension = split(filename, ".")[2] 
    return mimetypes[][exstension]
end


# Assign the paresd mimetypes
mimetypes[] = parsefile(datapath())

end