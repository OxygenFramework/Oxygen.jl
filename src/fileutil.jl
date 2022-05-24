module FileUtil 

    export file, getfiles, @iteratefiles

    current_directory = pwd()

    """
        file(folder::String, filename::String)

    Read in a file as a String (from the projects current working directory)
    """
    function file(filename::String)
        path = joinpath(current_directory, filename)
        return read(open(path), String)
    end


    """
        file(folder::String, filename::String)

    Read in a file from a specific folder as a String (from the projects current working directory)
    """
    function file(folder::String, filename::String)
        path = joinpath(current_directory, folder, filename)
        return read(open(path), String)
    end


    """
        getfiles(folder::String)

    Return all files inside a folder (searches nested folders)
    """
    function getfiles(folder::String)
        target_files::Array{String} = []
        for (root, _, files) in walkdir(folder)
            for file in files
                push!(target_files, joinpath(root, file))
            end
        end
        return target_files
    end

    """
        @iteratefiles(folder::String, func::Function)

    Walk through all files in a directory and apply a function to each file
    """
    macro iteratefiles(folder::String, func)
        local target_files::Array{String} = getfiles(folder)
        quote 
            local action = $(esc(func))
            for filepath in $target_files
                action(filepath)
            end  
        end
    end

end