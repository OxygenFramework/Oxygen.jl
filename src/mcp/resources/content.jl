# Resource content normalization and `resources/read` result serialization.
# Included into `MCP.Resources` by `../resources.jl`.

# ----------------------------------------------------------------------------
# Resource content serialization
# ----------------------------------------------------------------------------

# `resources/read` contents carry `uri`/`mimeType` plus exactly one of `text` or
# `blob`; the content-block shape (`type`/`resource`) is for tool results.
resource_text(uri::String, mime::AbstractString, content) :: Dict{String,Any} =
    Dict{String,Any}("uri" => uri, "mimeType" => String(mime), "text" => string(content))

resource_blob(uri::String, mime::AbstractString, bytes::AbstractVector{UInt8}) :: Dict{String,Any} =
    Dict{String,Any}("uri" => uri, "mimeType" => String(mime), "blob" => base64encode(bytes))

function resource_bytes(uri::String, mime::AbstractString,
                        bytes::AbstractVector{UInt8}) :: Dict{String,Any}

    return is_text_mime(mime) ? resource_text(uri, mime, String(bytes)) :
                                resource_blob(uri, mime, bytes)
end

# Normalize a pre-shaped content dict into a schema-valid ResourceContents: the
# `uri` is filled when missing, the declared MIME type becomes the default, and
# exactly one of `text`/`blob` must be present. Unknown keys (`annotations`,
# `_meta`, ...) pass through untouched. A malformed entry is an authoring bug,
# so it surfaces as -32603 rather than a client params error.
function normalize_content_entry(
    uri::String,
    declared_mime::Nullable{String},
    entry::AbstractDict) :: Dict{String,Any}

    content = string_keyed(entry)

    has_text = haskey(content, "text")
    has_blob = haskey(content, "blob")
    if has_text == has_blob
        detail = has_text ? "`text` and `blob` are mutually exclusive" :
                            "exactly one of `text` or `blob` is required"
        throw(MCPRequestError(MCP_INTERNAL_ERROR, "Invalid resource content: $detail"))
    end

    if !haskey(content, "uri")
        content["uri"] = uri
    elseif !(content["uri"] isa AbstractString)
        throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource content: `uri` must be a string"))
    end
    if has_text
        if !(content["text"] isa AbstractString)
            throw(MCPRequestError(
                MCP_INTERNAL_ERROR, "Invalid resource content: `text` must be a string"))
        end
    elseif !(content["blob"] isa AbstractString)
        throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource content: `blob` must be a base64 string"))
    end
    if !haskey(content, "mimeType") && !isnothing(declared_mime)
        content["mimeType"] = declared_mime
    end

    return content
end

"""
    resource_content(resource, uri, value) :: Dict

Serialize one resource content entry. `HTTP.Response` values honor their
`Content-Type`; `String`s become `text`; raw bytes become `text` for textual
media and base64 `blob` otherwise; a dict already carrying `text`/`blob` is
normalized (missing `uri`/`mimeType` filled, extra fields preserved); a `Pair`
overrides the entry's URI; anything else is JSON-encoded into `text`. The
resource's declared `mime_type` is the fallback when the value does not supply
one.
"""
function resource_content(resource::MCPResource, uri::String, value) :: Dict{String,Any}
    declared = resource.mime_type

    if value isa HTTP.Response
        return resource_bytes(uri, response_mime(value), response_bytes(value))
    elseif value isa AbstractString
        return resource_text(uri, something(declared, "text/plain"), value)
    elseif value isa AbstractVector{UInt8}
        return resource_bytes(uri, something(declared, HTTP.sniff(value)), value)
    elseif value isa Pair
        return resource_content(resource, string(value.first), value.second)
    elseif value isa AbstractDict && (haskey(value, "text") || haskey(value, "blob"))
        return normalize_content_entry(uri, declared, value)
    else
        return resource_text(uri, something(declared, "application/json"), JSON.json(value))
    end
end

# A dict entry inside a pre-shaped `contents` array is an authoring-provided
# ResourceContents, so it must already carry exactly one of `text`/`blob`;
# a missing or doubled pair is a server bug (-32603). Non-dict values keep the
# usual serialization (a `Pair` may still restate the entry URI).
function contents_entry(resource::MCPResource, uri::String, value) :: Dict{String,Any}
    return value isa AbstractDict ? normalize_content_entry(uri, resource.mime_type, value) :
                                    resource_content(resource, uri, value)
end

# Normalize a handler return value into a `resources/read` result. A vector of
# values becomes multiple contents, `Pair`s may restate the URI per entry, and a
# dict already shaped as a result (`"contents"`) has every entry normalized so
# the reply is always schema-valid.
function resource_result(resource::MCPResource, uri::String, value) :: Dict{String,Any}
    if value isa AbstractDict && haskey(value, "contents")
        raw = value["contents"]
        if !(raw isa AbstractVector && !(raw isa AbstractVector{UInt8}))
            throw(MCPRequestError(
                MCP_INTERNAL_ERROR, "Invalid resource result: `contents` must be an array"))
        end
        result = string_keyed(value)
        result["contents"] = Any[contents_entry(resource, uri, item) for item in raw]
        return result
    elseif value isa AbstractVector && !(value isa AbstractVector{UInt8})
        return Dict{String,Any}(
            "contents" => Any[resource_content(resource, uri, item) for item in value])
    else
        return Dict{String,Any}("contents" => Any[resource_content(resource, uri, value)])
    end
end

