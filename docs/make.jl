using Documenter
using Oxygen

makedocs(
    sitename = "Oxygen.jl",
    format = Documenter.HTML(),
    modules = [Oxygen]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/ndortega/Oxygen.jl.git",
    devbranch="develop"
)


