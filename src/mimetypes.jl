module MimeTypes 

using HTTP

export mimetype

global const mimetypes = Ref{Dict{String,String}}(Dict())

# pull down the latest mime.types
response = HTTP.get("https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types")

# parse all mime types 
content = split(String(response.body), "\n") 
for line in content
    if !isempty(line) && !startswith(line, "#")
        mimetype, exstenions... = split(line)
        for ext in exstenions 
            mimetypes[][ext] = mimetype
        end
    end
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

end