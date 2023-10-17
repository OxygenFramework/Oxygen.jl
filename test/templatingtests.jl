module TemplatingTests 
using MIMEs
using Test
using HTTP
using Mustache
using OteraEngine

include("../src/Oxygen.jl")
using .Oxygen

# ensure the init is called so we can load the extensions
Oxygen.__init__()


function clean_output(result::String)
    # handles running on windows with carrige returns
    if occursin("\r\n", result)
        return replace(result, "\r\n" =>"\n")
    else 
        return result
    end
end

function remove_trailing_newline(s::String)::String
    if !isempty(s) && last(s) == '\n'
        return s[1:end-1]
    end
    return s
end


data = Dict(
    "name" => "Chris",
    "value" => 10000,
    "taxed_value" => 10000 - (10000 * 0.4),
    "in_ca" => true
)

mustache_template = mt"""
Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}
"""

mustache_template_str = """
Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}
"""

expected_output = """
Hello Chris
You have just won 10000 dollars!
Well, 6000.0 dollars, after taxes.
"""

@testset "mustache() from string tests " begin 
    render = mustache(mustache_template_str, mime_type="text/plain")
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end

@testset "mustache() from string tests w/ content type" begin 
    render = mustache(mustache_template_str)
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end



@testset "mustache() from file no content type" begin 
    render = mustache("./content/mustache_template.txt")
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end

@testset "mustache() from file w/ content type" begin 
    render = mustache("./content/mustache_template.txt", mime_type="text/plain")
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end



@testset "mustache() from file with no content type" begin 
    render = mustache(open("./content/mustache_template.txt"))
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end

@testset "mustache() from file with content type" begin 
    render = mustache(open("./content/mustache_template.txt"), mime_type="text/plain")
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end



@testset "mustache() from template" begin 
    render = mustache(mustache_template)
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end

@testset "mustache() from template with content type" begin 
    render = mustache(mustache_template, mime_type="text/plain")
    response = render(data)
    @test response.body |> String |> clean_output == expected_output
end


@testset "mustache api tests" begin 

    mus_str = mustache(mustache_template_str)
    mus_tpl = mustache(mustache_template)
    mus_file = mustache("./content/mustache_template.txt")
    
    @get "/mustache/string" function()
        return mus_str(data)
    end
    
    @get "/mustache/template" function()
        return mus_tpl(data)
    end
    
    @get "/mustache/file" function()
        return mus_file(data)
    end
    
    r = internalrequest(HTTP.Request("GET", "/mustache/string"))
    @test r.status == 200
    @test r.body |> String |> clean_output == expected_output
    
    r = internalrequest(HTTP.Request("GET", "/mustache/template"))
    @test r.status == 200
    @test r.body |> String |> clean_output == expected_output
    
    r = internalrequest(HTTP.Request("GET", "/mustache/file"))
    @test r.status == 200
    @test r.body |> String |> clean_output == expected_output
    
end



@testset "otera() from string" begin 

    template = """
    <html>
        <head><title>MyPage</title></head>
        <body>
            {% if name=="watasu" %}
            your name is {{ name }}, right?
            {% end %}
            {% for i in 1 : 10 %}
            Hello {{i}}
            {% end %}
            {% with age = 15 %}
            and your age is {{ age }}.
            {% end %}
        </body>
    </html>
    """ |> remove_trailing_newline

    expected_output = """
    <html>
        <head><title>MyPage</title></head>
        <body>
            your name is watasu, right?
            Hello 1
            Hello 2
            Hello 3
            Hello 4
            Hello 5
            Hello 6
            Hello 7
            Hello 8
            Hello 9
            Hello 10
            and your age is 15.
        </body>
    </html>
    """ |> remove_trailing_newline

    # detect content type
    data = Dict("name" => "watasu")
    render = otera(template)
    result = render(tmp_init=data)
    @test result.body |> String |> clean_output == expected_output

    # with explicit content type
    data = Dict("name" => "watasu")
    render = otera(template; mime_type="text/html")
    result = render(tmp_init=data)
    @test result.body |> String |> clean_output == expected_output

end


@testset "otera() from template file" begin 

    expected_output = """
    <html>
        <head><title>MyPage</title></head>
        <body>
            your name is watasu, right?
            Hello 1
            Hello 2
            Hello 3
            Hello 4
            Hello 5
            Hello 6
            Hello 7
            Hello 8
            Hello 9
            Hello 10
            and your age is 15.
        </body>
    </html>
    """ |> remove_trailing_newline

    data = Dict("name" => "watasu")

    render = otera("./content/otera_template.html")
    result = render(tmp_init=data)
    @test result.body |> String |> clean_output == expected_output

    # with explicit content type
    render = otera(open("./content/otera_template.html"); mime_type="text/html")
    result = render(tmp_init=data)
    @test result.body |> String |> clean_output == expected_output
end


@testset "otera() from template file with no args" begin 

    expected_output = """
    <html>
        <head><title>MyPage</title></head>
        <body>
            your name is watasu, right?
            Hello 1
            Hello 2
            Hello 3
            Hello 4
            Hello 5
            Hello 6
            Hello 7
            Hello 8
            Hello 9
            Hello 10
            and your age is 15.
        </body>
    </html>
    """ |> remove_trailing_newline

    render = otera("./content/otera_template_no_vars.html")
    result = render()
    @test result.body |> String |> clean_output == expected_output

    render = otera("./content/otera_template_no_vars.html", mime_type="text/html")
    result = render()
    @test result.body |> String |> clean_output == expected_output
end


@testset "otera() running julia code in template" begin 
    template = "```3 ^ 3```. Hello {{ name }}!"
    expected_output = "27. Hello world!"
    render = otera(template)
    result = render(tmp_init=Dict("name"=>"world"))
    @test result.body |> String |> clean_output == expected_output

    template = """
    <html>
        <head><title>Jinja Test Page</title></head>
        <body>
            Hello, ```name```!
        </body>
    </html>
    """ |> remove_trailing_newline

    expected_output = """
    <html>
        <head><title>Jinja Test Page</title></head>
        <body>
            Hello, world!
        </body>
    </html>
    """ |> remove_trailing_newline

    render = otera(template)
    result = render(jl_init=Dict("name"=>"world"))
    @test result.body |> String |> clean_output == expected_output
end

@testset "otera() combined tmp_init & jl_init test" begin 
    template = "```parse(Int, value) ^ 3```. Hello {{name}}!"
    expected_output = "27. Hello World!"
    render = otera(template)
    result = render(tmp_init=Dict("name" => "World"), jl_init=Dict("value" => "3"))
end

@testset "otera() combined tmp_init & jl_init test with content type" begin 
    template = "```parse(Int, value) ^ 3```. Hello {{name}}!"
    expected_output = "27. Hello World!"
    render = otera(template, mime_type = "text/plain")
    result = render(tmp_init=Dict("name" => "World"), jl_init=Dict("value" => "3"))
end



end