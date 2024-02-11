# Some deprecated stuff

function enabledocs()
    @warn "This function is deprecated in favour of keyword argument `docs` in serve"
end

function disabledocs()
    error("This function is deprecated in favour of keyword argument `docs` in serve")
end

function isdocsenabled()
    @warn "This function is deprecated in favour of keyword argument `docs` in serve"
    return true # as set in serve
end

# I could check if it is defined and set it that way
# global SCHEMA = Core.AutoDoc.defaultSchema()


"""
    configdocs(docs_url::String = "/docs", schema_url::String = "/schema")

Configure the default docs and schema endpoints
"""
function configdocs(docs_url::String, schema_url::String)
    configdocs(; docspath = docs_url, schemapath = schema_url)
end
