using HTTP

export readfile, mountfolder

"""
    readfile(filepath::String)

Reads a file as a String
"""
function readfile(filepath::String)
    return read(filepath, String)
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
    iteratefiles(func::Function, folder::String)

Walk through all files in a directory and apply a function to each file
"""
function iteratefiles(func::Function, folder::String)
    for filepath in getfiles(folder)
        func(filepath)
    end
end

"""
Helper function that returns everything before a designated substring
"""
function getbefore(input::String, target) :: String
    result = findfirst(target, input)
    index = first(result) - 1
    return input[begin:index]
end

"""
    mountfolder(folder::String, mountdir::String, addroute::Function)

This function is used to discover files & register them to the router while  
leaving the `addroute` function to determine how to register the files
"""
function mountfolder(folder::String, mountdir::String, addroute)
    
    separator = Base.Filesystem.path_separator

    # track all registered paths 
    paths = Dict{String, Bool}()

    iteratefiles(folder) do filepath

        # remove the first occurrence of the root folder from the filepath before "mounting"
        cleanedmountpath = replace(filepath, "$(folder)$(separator)" => "", count=1)

        # make sure to replace any system path separator with "/"
        cleanedmountpath = replace(cleanedmountpath, separator => "/")

        # generate the path to mount the file to
        mountpath = mountdir == "/" || isnothing(mountdir) || isempty(mountdir) || all(isspace, mountdir) ? "/$cleanedmountpath" : "/$mountdir/$cleanedmountpath"

        paths[mountpath] = true 
        # register the file route
        addroute(mountpath, filepath)

        # also register file to the root of each subpath if this file is an index.html
        if endswith(mountpath, "/index.html")

            # /docs/metrics and /docs/metrics/ are the same path 
            # when HTTP is considered. 

            # # add the route with the trailing "/" character
            # trimmedpath = getbefore(mountpath, "index.html")
            # paths[trimmedpath] = true
            # addroute(trimmedpath, filepath)

            # add the route without the trailing "/" character
            bare_path = getbefore(mountpath, "/index.html")
            paths[bare_path] = true
            addroute(bare_path, filepath)
        end
    end
    
end
