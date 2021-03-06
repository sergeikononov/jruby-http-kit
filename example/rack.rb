$LOAD_PATH << '../lib'

require 'http_kit'
require 'http_kit/server'
require 'example/hello_world'

server = HttpKit::Server.run(HelloWorld.new)

Signal.trap("TERM") do
  server.stop()
end
