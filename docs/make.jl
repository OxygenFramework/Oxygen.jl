using Documenter
using Oxygen

makedocs(
    sitename = "Oxygen",
    format = Documenter.HTML(),
    modules = [Oxygen]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
