module CronManagementDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

get("/data") do
    Dict("msg" => "hello")
end

get("/random/sm") do
    sleep(rand(0.1:0.30))
    "small random"
end

get("/random/md") do
    sleep(rand(0.30:0.70))
    "small random"
end

get("/random/lg") do
    sleep(rand(0.30:1))
    "random"
end

serve()

end