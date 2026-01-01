module ExtractIPTests

using Test
using HTTP
using Sockets
using Oxygen.Middleware.ExtractIPMiddleware: extract_ip

@testset "extract_ip function tests" begin

    # Helper function to create a request with specific headers and context IP
    function create_request(headers, context_ip::IPAddr = IPv4("127.0.0.1"))
        req = HTTP.Request("GET", "/", headers, "")
        req.context[:ip] = context_ip
        return req
    end

    @testset "CF-Connecting-IP header (highest priority)" begin
        req = create_request(["CF-Connecting-IP" => "192.168.1.100"])
        @test extract_ip(req) == IPv4("192.168.1.100")
    end

    @testset "True-Client-IP header (priority 2)" begin
        req = create_request(["True-Client-IP" => "10.0.0.50"])
        @test extract_ip(req) == IPv4("10.0.0.50")
    end

    @testset "X-Forwarded-For header (priority 3, single IP)" begin
        req = create_request(["X-Forwarded-For" => "203.0.113.1"])
        @test extract_ip(req) == IPv4("203.0.113.1")
    end

    @testset "X-Forwarded-For header (priority 3, multiple IPs, use first)" begin
        req = create_request(["X-Forwarded-For" => "203.0.113.1, 198.51.100.2, 192.0.2.3"])
        @test extract_ip(req) == IPv4("203.0.113.1")
    end

    @testset "X-Forwarded-For header (priority 3, with spaces)" begin
        req = create_request(["X-Forwarded-For" => " 203.0.113.1 , 198.51.100.2 "])
        @test extract_ip(req) == IPv4("203.0.113.1")
    end

    @testset "X-Real-IP header (priority 4)" begin
        req = create_request(["X-Real-IP" => "172.16.0.10"])
        @test extract_ip(req) == IPv4("172.16.0.10")
    end

    @testset "Priority order: CF-Connecting-IP overrides others" begin
        req = create_request([
            "X-Forwarded-For" => "203.0.113.1",
            "CF-Connecting-IP" => "192.168.1.100",
            "True-Client-IP" => "10.0.0.50"
        ])
        @test extract_ip(req) == IPv4("192.168.1.100")
    end

    @testset "Priority order: True-Client-IP overrides X-Forwarded-For and X-Real-IP" begin
        req = create_request([
            "X-Forwarded-For" => "203.0.113.1",
            "X-Real-IP" => "172.16.0.10",
            "True-Client-IP" => "10.0.0.50"
        ])
        @test extract_ip(req) == IPv4("10.0.0.50")
    end

    @testset "Priority order: X-Forwarded-For overrides X-Real-IP" begin
        req = create_request([
            "X-Real-IP" => "172.16.0.10",
            "X-Forwarded-For" => "203.0.113.1"
        ])
        @test extract_ip(req) == IPv4("203.0.113.1")
    end

    @testset "Fallback to req.context[:ip] when no headers" begin
        req = create_request([], IPv4("127.0.0.1"))
        @test extract_ip(req) == IPv4("127.0.0.1")
    end

    @testset "Fallback to req.context[:ip] when headers are empty" begin
        req = create_request(["X-Forwarded-For" => ""], IPv4("127.0.0.1"))
        @test extract_ip(req) == IPv4("127.0.0.1")
    end

    @testset "IPv6 support" begin
        req = create_request(["CF-Connecting-IP" => "2001:db8::1"])
        @test extract_ip(req) == IPv6("2001:db8::1")
    end

    @testset "Case insensitive header matching" begin
        req = create_request(["cf-connecting-ip" => "192.168.1.100"])  # lowercase
        @test extract_ip(req) == IPv4("192.168.1.100")
    end

end

end