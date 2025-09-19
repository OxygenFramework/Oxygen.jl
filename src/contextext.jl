module ContextExt

using ..AppContext: ServerContext, ExtensionBuilder

export @register_ext

function module_to_key(mod::Module, scope)
    rootmodule = Base.moduleroot(mod)
    pkg = Base.PkgId(rootmodule)
    if scope == :project
        return Symbol("$(pkg.uuid)__$(pkg.name)")
    elseif scope == :module
        qualified = join(fullname(mod, "__"))
        return Symbol("$(pkg.uuid)__$(qualified)")
    else
        error("Unknown scope $(scope)")
    end
end

function build!(builder::ExtensionBuilder)
    result = (; builder.bits...)
    empty!(builder.bits)
    return result
end

function initialize_exts!(ctx::ServerContext)
    ctx.exts[] = build!(ctx.ext_builder)
end

function install_ext!(ctx::ServerContext, args...; kwargs...)
    install_ext!(ctx.ext_builder, args...; kwargs...)
end

function install_ext!(builder::ExtensionBuilder, namespace::Symbol, value)
    push!(builder.bits, namespace => value)
end

function install_ext!(builder::ExtensionBuilder, mod::Module, value; scope=:project)
    install_ext!(builder, module_to_key(mod, scope), value)
end

function get_ext(ctx::ServerContext, mod::Module; scope=:project)
    namespace = module_to_key(mod, scope)
    return get_ext(ctx, namespace)
end

function get_ext(ctx::ServerContext, namespace::Symbol)
    return ctx.exts[][namespace]
end

function register_ext(mod::Module, type::Type; scope=:project)
    key = module_to_key(mod, scope)

    function bound_install_ext!(ctx::ServerContext, value)
        install_ext!(ctx.ext_builder, key, value)
    end

    function bound_get_ext!(ctx::ServerContext)
        return get_ext(ctx, key)
    end

    return (
        bound_get_ext!,
        bound_install_ext!
    )
end

macro register_ext(expr)
    :(@register_ext :project $(esc(expr)))
end

# $(esc(:install_ext)), $(esc(:get_ext)) = 
macro register_ext(scope, type)
    quote
        register_ext($(__module__), $(esc(type)); scope=$(esc(scope)))
    end
end

end