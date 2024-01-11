module CronManagementDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

get("/data") do
    Dict("msg" => "hello")
end

get("/random/sm") do
    sleep(rand(0.01:0.03))
    "small random"
end

get("/random/md") do
    sleep(rand(0.03:0.07))
    "small random"
end

get("/random/lg") do
    sleep(rand(0.07:.1))
    "random"
end

serve()

end