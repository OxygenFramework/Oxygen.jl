module FastApi 

    include("wrapper.jl")
    using .Wrapper

    include("util.jl")
    using .Util

    include("fileutil.jl")
    using .FileUtil

    export @get, @post, @put, @patch, @delete, @register, @route, @staticfiles, @mount,
            serve, queryparams, binary, text, json, countargs,
            getvarname, getvartype, absfile, file
    
end 