# Folder-backed resources registered with `register_resource_folder!`.
# Included into `MCP.Resources` by `../resources.jl`.

# ----------------------------------------------------------------------------
# Folder-backed resources
# ----------------------------------------------------------------------------

# Extension => MIME type for the folder helper. `HTTP.sniff` covers the rest.
const FOLDER_MIME_TYPES = Dict{String,String}(
    "txt"      => "text/plain",
    "md"       => "text/markdown",
    "markdown" => "text/markdown",
    "html"     => "text/html",
    "htm"      => "text/html",
    "css"      => "text/css",
    "js"       => "text/javascript",
    "mjs"      => "text/javascript",
    "json"     => "application/json",
    "xml"      => "application/xml",
    "csv"      => "text/csv",
    "log"      => "text/plain",
    "jl"       => "text/plain",
    "toml"     => "application/toml",
    "yaml"     => "application/yaml",
    "yml"      => "application/yaml",
    "svg"      => "image/svg+xml",
    "png"      => "image/png",
    "jpg"      => "image/jpeg",
    "jpeg"     => "image/jpeg",
    "gif"      => "image/gif",
    "webp"     => "image/webp",
    "pdf"      => "application/pdf",
    "zip"      => "application/zip",
)

# True when `candidate` is `root` itself or sits below it.
function is_within(root::String, candidate::String) :: Bool
    separator = Sys.iswindows() ? "\\" : "/"
    prefix = endswith(root, separator) ? root : root * separator
    return candidate == root || startswith(candidate, prefix)
end

folder_not_found(uri::String) = throw(MCPRequestError(
    MCP_RESOURCE_NOT_FOUND, "Resource not found", Dict{String,Any}("uri" => uri)))

function folder_mime(path::AbstractString, bytes::Vector{UInt8}, mime_types) :: String
    extension = lowercase(splitext(path)[2])
    key = startswith(extension, ".") ? extension[2:end] : extension
    if !isnothing(mime_types)
        if haskey(mime_types, extension)
            return String(mime_types[extension])
        end
        if haskey(mime_types, key)
            return String(mime_types[key])
        end
        # Caller-supplied keys are matched case-insensitively too, with or
        # without the leading dot.
        for (candidate, mime) in mime_types
            if !(candidate isa AbstractString)
                continue
            end
            normalized = lowercase(String(candidate))
            if normalized == extension || normalized == key
                return String(mime)
            end
        end
    end
    if haskey(FOLDER_MIME_TYPES, key)
        return FOLDER_MIME_TYPES[key]
    end
    return HTTP.sniff(bytes)
end

# Read a regular file through an `O_NOFOLLOW` handle on POSIX so a symlink
# swapped in after the `realpath` check cannot redirect the read (the parent
# directories are already canonical at that point). Windows has no equivalent
# here and falls back to a plain read. Errors (deleted file, ELOOP, ...) are
# the caller's to map.
function read_folder_file(path::String) :: Vector{UInt8}
    if Sys.isunix()
        handle = Base.Filesystem.open(path,
            Base.Filesystem.JL_O_RDONLY | Base.Filesystem.JL_O_NOFOLLOW)
        try
            io = Base.fdio(reinterpret(Int32, Base.Filesystem.fd(handle)))
            return read(io)
        finally
            Base.Filesystem.close(handle)
        end
    end
    return read(path)
end

"""
    folder_resource_content(root, prefix, path; hidden=false, mime_types=nothing)

Read one file for a folder-backed resource. `path` is the decoded reserved
capture (it may contain `/`). `.`/`..`/backslash segments, NUL bytes, `:` on
Windows (drive/alternate-data-stream syntax), and (unless `hidden=true`)
dotfiles are rejected; the resolved target is checked with `realpath` against
the canonical root and read through a no-follow handle, so a symlink cannot
escape. Missing or unreadable files throw `MCP_RESOURCE_NOT_FOUND`, which
`read_resource` maps per era.
"""
function folder_resource_content(
    root::String,
    prefix::String,
    path::String;
    hidden::Bool=false,
    mime_types=nothing)

    uri = prefix * path
    invalid = isempty(path) || occursin('\0', path) || occursin('\\', path) ||
              (Sys.iswindows() && occursin(':', path))
    if invalid
        folder_not_found(uri)
    end

    segments = split(path, '/'; keepempty=false)
    if isempty(segments)
        folder_not_found(uri)
    end
    for segment in segments
        if segment == "." || segment == ".."
            folder_not_found(uri)
        end
        if !hidden && startswith(segment, ".")
            folder_not_found(uri)
        end
    end

    real_root = try
        realpath(root)
    catch
        folder_not_found(uri)
    end
    real_file = try
        realpath(joinpath(real_root, segments...))
    catch
        folder_not_found(uri)
    end

    if !(is_within(real_root, real_file) && isfile(real_file))
        folder_not_found(uri)
    end

    bytes = try
        read_folder_file(real_file)
    catch
        folder_not_found(uri)
    end
    mime = folder_mime(real_file, bytes, mime_types)
    return HTTP.Response(200, ["Content-Type" => mime], bytes)
end

"""
    register_resource_folder!(ctx, prefix, directory; name=nothing, description=nothing,
                              title=nothing, hidden=false, mime_types=nothing,
                              annotations=nothing, icons=nothing)

Register a resource template at `prefix * "{+path}"` serving regular files below
`directory`. The reserved capture spans `/`, so nested folders work; every read
is sanitized (see `folder_resource_content`). `mime_types` maps a file
extension (with or without the leading dot, matched case-insensitively) to a
MIME type; otherwise a built-in table and `HTTP.sniff` decide. `name` defaults
to the directory's basename.
"""
function register_resource_folder!(
    ctx::ServerContext,
    prefix::String,
    directory::String;
    name=nothing,
    description=nothing,
    title=nothing,
    hidden::Bool=false,
    mime_types::Union{Nothing,AbstractDict}=nothing,
    annotations=nothing,
    icons=nothing)

    if isempty(prefix)
        throw(ArgumentError("An MCP resource folder prefix cannot be empty"))
    end
    if occursin('{', prefix)
        throw(ArgumentError(
            "MCP resource folder prefix `$prefix` cannot contain `{`; the helper appends `{+path}`"))
    end
    if !isdir(directory)
        throw(ArgumentError("MCP resource folder `$directory` is not a directory"))
    end

    root = realpath(abspath(directory))
    uri = prefix * "{+path}"
    desc = isnothing(description) ? "Files served under $prefix" : string(description)
    folder_name = basename(root)
    wirename = if isnothing(name)
        isempty(folder_name) || folder_name == "/" ? "files" : folder_name
    else
        string(name)
    end

    handler = function (path::String)
        return folder_resource_content(root, prefix, path; hidden=hidden, mime_types=mime_types)
    end

    return register_resource!(ctx, uri, desc, handler;
                              name=wirename, title=title,
                              annotations=annotations, icons=icons)
end
