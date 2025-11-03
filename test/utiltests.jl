module UtilTests
using Test
using Oxygen.Core.Util

@testset "join_url_path" begin
    # prefix == nothing returns route verbatim (current implementation)
    @test join_url_path(nothing, "/users") == "/users"
    @test join_url_path(nothing, "users") == "users"
    @test join_url_path(nothing, "/") == "/"

    # prefix without trailing slash, route with leading slash
    @test join_url_path("/api", "/users") == "/api/users"
    @test join_url_path("/api", "/users/") == "/api/users/"

    # prefix with trailing slash, route without leading slash
    @test join_url_path("/api/", "users") == "/api/users"
    @test join_url_path("api/", "users") == "api/users"   # preserves prefix exactly as implemented

    # mixed variations - ensure no duplicate slashes and trailing slash preserved
    @test join_url_path("/api/", "/users") == "/api/users"
    @test join_url_path("/api/", "/users/") == "/api/users/"

    # empty route
    @test join_url_path("/api", "") == "/api/"
    @test join_url_path("", "/") == "/"
end

@testset "join_url_path additional edge cases" begin
    # empty route cases
    @test join_url_path(nothing, "") == ""            # current implementation returns route verbatim
    @test join_url_path("", "") == "/"                # prefix "" produces root

    # multiple leading slashes in route should be normalized by lstrip
    @test join_url_path("/api", "///users") == "/api/users"

    # route with query string preserved
    @test join_url_path("/api", "/users/?q=1") == "/api/users/?q=1"
    @test join_url_path(nothing, "/users/?q=1") == "/users/?q=1"

    # prefix == "/" behaves as expected
    @test join_url_path("/", "/users") == "/users"
    @test join_url_path("/", "/") == "/"

    # prefix made only of slashes (demonstrates current behavior)
    @test join_url_path("///", "/users") == "///users"
end

@testset "join_url_path exhaustive edge cases" begin
    # prefix variations (leading/trailing slash differences)
    @test join_url_path("api", "/users") == "api/users"
    @test join_url_path("/api", "users") == "/api/users"
    @test join_url_path("", "users") == "/users"
    @test join_url_path("/", "users") == "/users"
    @test join_url_path("/", "/") == "/"

    # route consisting only of slashes -> treat as root of prefix
    @test join_url_path("/api", "///") == "/api/"

    # query string and fragment must be preserved
    @test join_url_path("/api", "/users/?q=1#frag") == "/api/users/?q=1#frag"
    @test join_url_path(nothing, "/users/?q=1#frag") == "/users/?q=1#frag"

    # percent-encoding and unicode preserved
    @test join_url_path("/путь", "/пользователь") == "/путь/пользователь"
    @test join_url_path("/api", "/file%20name.txt") == "/api/file%20name.txt"

    # backslashes in route are unchanged (function should not convert separators)
    @test join_url_path("/api", "\\windows\\path") == "/api/\\windows\\path"

    # very long inputs (performance / correctness for large strings)
    longp = "/" * repeat("a", 1000)
    longr = "/" * repeat("b", 1000)
    @test join_url_path(longp, longr) == "/" * repeat("a", 1000) * "/" * repeat("b", 1000)
end

end