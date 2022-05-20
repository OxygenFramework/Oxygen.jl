module Oxygen 

    include("wrapper.jl")
    using .Wrapper

    include("fileutil.jl")
    using .FileUtil

    export @get, @post, @put, @patch, @delete, @register, @route, @staticfiles,
            serve, internalrequest, queryparams, binary, text, json, html, file,
            getfilecontenttype
    
end 