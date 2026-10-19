# MCP content-block serialization for tool and prompt results.
# Included into `MCP.Serialization` by `../serialization.jl`.

# ----------------------------------------------------------------------------
# Content serialization (shared by tools and prompts)
# ----------------------------------------------------------------------------

# The content block types a handler may return pre-shaped (they pass through).
const MCP_CONTENT_TYPES = ("text", "image", "audio", "resource_link", "resource")

# MIME types carried in a `text` content block even without a `text/` prefix.
function is_text_mime(mime::AbstractString)::Bool
    m = lowercase(mime)
    return startswith(m, "text/") ||
           m in ("application/json", "application/xml", "application/javascript",
                 "application/toml", "application/yaml", "application/x-yaml") ||
           endswith(m, "+json") || endswith(m, "+xml")
end

# The media type of an `HTTP.Response`, with any parameters (`; charset=...`) dropped.
function response_mime(resp::HTTP.Response)::String
    header = HTTP.header(resp, "Content-Type", "application/octet-stream")
    return lowercase(strip(split(String(header), ';')[1]))
end

text_block(content)::Dict{String,Any} = Dict{String,Any}("type" => "text", "text" => string(content))

"""
    binary_block(bytes, mime) :: Dict

Serialize raw bytes into the MCP content block that best fits `mime`: an `image`
or `audio` block (base64 `data`), a `text` block for textual media, or an
embedded `resource` (base64 `blob`) for any other binary, since MCP has no bare
binary content block.
"""
function binary_block(bytes::Vector{UInt8}, mime::String)::Dict{String,Any}
    mime = String(strip(split(mime, ';')[1]))
    m = lowercase(mime)
    kind = startswith(m, "image/") ? "image" : startswith(m, "audio/") ? "audio" : nothing
    if !isnothing(kind)
        return Dict{String,Any}("type" => kind, "data" => base64encode(bytes), "mimeType" => mime)
    elseif is_text_mime(m)
        return text_block(String(bytes))
    else
        return Dict{String,Any}(
            "type" => "resource",
            "resource" => Dict{String,Any}(
                "uri" => "oxygen://blob",
                "mimeType" => mime,
                "blob" => base64encode(bytes),
            ),
        )
    end
end

response_block(resp::HTTP.Response)::Dict{String,Any} =
    binary_block(response_bytes(resp), response_mime(resp))

"""
    content_block(value) :: Dict

Serialize a handler return value into a single MCP content block. `HTTP.Response`
values honor their `Content-Type` (so `html`/`json`/`text`/`binary`/`file` produce
`text` blocks and image/audio responses produce base64 media blocks); a dict
carrying a known content `type` passes through; anything else is JSON-encoded
into a text block.
"""
content_block(value::HTTP.Response) :: Dict{String,Any} = response_block(value)
content_block(value::AbstractString) :: Dict{String,Any} = text_block(String(value))
content_block(value::AbstractVector{UInt8}) :: Dict{String,Any} = binary_block(value, HTTP.sniff(value))

# Dispatch is by type, not value, so the "known content type" test has to stay
# inside the `AbstractDict` method; a plain dict falls back to JSON text here
# because the `Any` method below can never be more specific than this one.
function content_block(value::AbstractDict) :: Dict{String,Any}
    if get(value, "type", nothing) in MCP_CONTENT_TYPES 
        return value
    end
    return text_block(JSON.json(value))
end

# Default case: anything not matched above is JSON-encoded into a text block.
content_block(value::Any) :: Dict{String,Any} = text_block(JSON.json(value))

function content_result(block::Dict{String,Any}, structured_content=nothing)::Dict{String,Any}
    result = Dict{String,Any}(
        "content" => Any[block],
        "isError" => false,
    )
    if !isnothing(structured_content)
        result["structuredContent"] = structured_content
    end
    return result
end

function toolresult(value; structured::Bool=true)::Dict{String,Any}
    if isnothing(value)
        # No result value (a handler returning `nothing`, or an adopted channel
        # that closed without a `result` marker): the answer is empty content.
        return Dict{String,Any}("content" => Any[], "isError" => false)
    elseif value isa HTTP.Response || 
        value isa AbstractString ||
        value isa AbstractVector{UInt8} ||
        (value isa AbstractDict && get(value, "type", nothing) in MCP_CONTENT_TYPES)
        return content_result(content_block(value))
    else
        encoded = JSON.json(value)
        # CallToolResult.structuredContent MUST be a JSON object per the MCP
        # spec; a scalar or array result has no valid structured form, so it is
        # omitted (the JSON still travels as text content). Revisions that do
        # not emit structuredContent skip the decode entirely.
        parsed = structured && startswith(lstrip(encoded), "{") ? JSON.parse(encoded) : nothing
        return content_result(text_block(encoded), parsed)
    end
end

"""
    tool_success_result(value; spec) :: Dict

The result of a completed tool call: the handler's return value serialized into
content blocks, with `structuredContent` emitted only for revisions that
introduced it (2025-06-18+). Shared by the buffered and streamed `tools/call`
paths so both produce identical bytes.
"""
function tool_success_result(value; spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return toolresult(value; structured=emits_structured_content(spec))
end
