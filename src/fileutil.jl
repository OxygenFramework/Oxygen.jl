module FileUtil 

    export file, getfiles

    current_directory = pwd()

    function file(filename::String)
        path = joinpath(current_directory, filename)
        return read(open(path), String)
    end

    function file(folder::String, filename::String)
        path = joinpath(current_directory, folder, filename)
        return read(open(path), String)
    end

    function getfiles(folder::String)
        target_files::Array{String} = []
        for (root, _, files) in walkdir(folder)
            for file in files
                push!(target_files, joinpath(root, file))
            end
        end
        return target_files
    end


end