# Some deprecated stuff

function enabledocs()
    @warn "This function is deprecated in favour of keyword argument `docs` in serve"
end

function disabledocs()
    throw("This function is deprecated in favour of keyword argument `docs` in serve")
end

function isdocsenabled()
    @warn "This function is deprecated in favour of keyword argument `docs` in serve"
    return true # as set in serve
end

"""
    configdocs(docspath::String = "/docs", schemapath::String = "/schema")

Configure the default docs and schema endpoints
"""
function configdocs(docspath::String = "/docs", schemapath::String = "/schema")
    
    @warn "This function is deprecated in favour of keyword argument `docspath` and `schemapath` in serve"

    docspath == "/docs" || throw("""docspath is not not "/docs" """)
    schemapath == "/schema" || throw("""schemapat is not not "/schema" """)

    #CONTEXT[] = Context(CONTEXT[]; docspath, schemapath)

    return
end
