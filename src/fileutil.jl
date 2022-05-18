module FileUtil 

    export absfile, file

    current_directory = pwd()

    function absfile(filepath::String)
        return read(open(filepath), String)
    end

    function file(filename::String)
        path = joinpath(current_directory, filename)
        return read(open(path), String)
    end

    function file(folder::String, filename::String)
        path = joinpath(current_directory, folder, filename)
        return read(open(path), String)
    end

end