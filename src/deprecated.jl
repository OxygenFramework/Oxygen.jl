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
    @warn "This function is deprecated in favour of keyword argument `docs_path` and `schema_path` in serve"
    CONTEXT[].docs.docspath[] = docspath
    CONTEXT[].docs.schemapath[] = schemapath
    return
end

# v1.8.0 - Deprecate the British spelling of the macro in favor of the more internationally recognized version  
macro oxidise()
    @warn "The spelling of the `@oxidise` macro has been deprecated in favor of `@oxidize`"
    esc(:(@oxidize))
end



