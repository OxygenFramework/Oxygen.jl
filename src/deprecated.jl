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

