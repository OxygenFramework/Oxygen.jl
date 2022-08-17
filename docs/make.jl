using Documenter
using Oxygen

makedocs(
    sitename = "Oxygen.jl",
    format = Documenter.HTML(),
    modules = [Oxygen],
    pages = [
        "Overview" => "index.md",
        "api.md",
        "Manual" => [
            "tutorial/first_steps.md",
            "tutorial/request_types.md",
            "tutorial/path_parameters.md",
            "tutorial/query_parameters.md",
            "tutorial/request_body.md",
            "tutorial/bigger_applications.md",
            "tutorial/oauth2.md"
        ]
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/ndortega/Oxygen.jl.git"
)


