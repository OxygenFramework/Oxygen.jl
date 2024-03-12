module ProtobufTests

using Test
using HTTP
using ProtoBuf
using Oxygen: protobuf

include("messages/people_pb.jl");
using .people_pb: People, Person

include("messages/test_pb.jl");
using .test_pb: MyMessage 

@testset "Protobuf decoder test" begin
    message = MyMessage(-1, ["a", "b"])
    req::HTTP.Request = protobuf(message, "/data")

    decoded_msg = protobuf(req, MyMessage)

    @test decoded_msg isa MyMessage
    @test decoded_msg.a == -1
    @test decoded_msg.b == ["a", "b"]
end

@testset "Protobuf People Decoder test" begin
    message = People([
        Person("John Doe", 20),
        Person("Jane Doe", 25),
        Person("Alice", 30),
        Person("Bob", 35),
        Person("Charlie", 40)
    ])

    req::HTTP.Request = protobuf(message, "/data", method="POST")

    decoded_msg = protobuf(req, People)

    @test decoded_msg isa People
    for person in decoded_msg.people
        @test person isa Person
    end
end


@testset "Protobuf encoder test" begin

    message = MyMessage(-1, ["a", "b"])
    response = protobuf(message)

    @test response isa HTTP.Response
    @test response.status == 200
    @test response.body isa Vector{UInt8}
    @test HTTP.header(response, "Content-Type") == "application/octet-stream"
    @test HTTP.header(response, "Content-Length") == string(sizeof(response.body))
end


@testset "Protobuf People encoder test" begin
    message = People([
        Person("John Doe", 20),
        Person("Jane Doe", 25),
        Person("Alice", 30),
        Person("Bob", 35),
        Person("Charlie", 40)
    ])

    response = protobuf(message)

    @test response isa HTTP.Response
    @test response.status == 200
    @test response.body isa Vector{UInt8}
    @test HTTP.header(response, "Content-Type") == "application/octet-stream"
    @test HTTP.header(response, "Content-Length") == string(sizeof(response.body))
end


end