module FileUtil

export file, getfiles, @iteratefiles

"""
    file(filepath::String)

Reads a file as a String
"""
function file(filepath::String)
    return read(open(filepath), String)
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
