module FileUtil 

    export file, getcontenttype, getfilecontenttype

    current_directory = pwd()

    function file(filename::String)
        path = joinpath(current_directory, filename)
        return read(open(path), String)
    end

    function file(folder::String, filename::String)
        path = joinpath(current_directory, folder, filename)
        return read(open(path), String)
    end

    function getfilecontenttype(filename::String)
        if endswith(filename, ".html")
            return "text/html"
        else
            return "text/plain"
        end
    end

    function getcontenttype(content::String)
        if startswith(content, "<!DOCTYPE html>")
            return "text/html"
        else
            return "text/plain"
        end
    end

end