module WebSocketDemo
using Dates
using HTTP
using HTTP.WebSockets: send
using Oxygen

@get "/" function()
    html("""
    <html>
        <head>
            <meta charset="UTF-8">
            <title>WebSocket demo</title>
        </head>
        <body>
            <h3>Sent messages:</h3>
            <ul id="list"></ul>
        </body>
        <script>
            const socket = new WebSocket("ws://127.0.0.1:8080/ws");
            socket.onopen = function(event) {
                setInterval(function() {
                    const message = "Hello, server! What time is it?";
                    socket.send(message);
                    console.log('Sent:', message);
                }, 1000);
            };
            socket.onmessage = function(event) {
                console.log('Received:', event.data);
                const newElement = document.createElement("li");
                const messageList = document.getElementById("list");
                newElement.textContent = event.data;
                messageList.appendChild(newElement);
            };
            socket.onerror = function(error) {
                console.log('WebSocket Error:', error);
            };
        </script>
        </html>
    """)
end

@websocket "/ws" function(ws::HTTP.WebSocket)
    for msg in ws
        @info "Received message: $msg"
        send(ws, "The time is: $(now())")
    end
end

serve()

end