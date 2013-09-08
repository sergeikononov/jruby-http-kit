require 'rack/rewindable_input'

module HttpKit

  java_import org.httpkit.HttpUtils;

  class HttpHandler < org.httpkit.server.RackHttpHandler
    field_reader :req
    field_reader :cb
    field_reader :handler

    def req_to_rack(req)
      env = {}

      body = req.getBody() || Rack::RewindableInput.new(StringIO.new(""))

      env["SERVER_SOFTWARE"]      = "HTTP Kit"
      env["SERVER_NAME"]          = req.serverName
      env["rack.input"]           = body
      env["rack.version"]         = [1, 0]
      env["rack.errors"]          = $stderr
      env["rack.multithread"]     = true
      env["rack.multiprocess"]    = false
      env["rack.run_once"]        = false
      env["REQUEST_METHOD"]       = req.method.KEY.to_s.gsub(':', '').upcase
      env["REQUEST_PATH"]         = ""
      env["PATH_INFO"]            = ""
      env["REQUEST_URI"]          = req.uri
      env["HTTP_VERSION"]         = "HTTP/1.1"
      env["HTTP_HOST"]            = "localhost:8080"
      env["HTTP_CONNECTION"]      = "keep-alive"
      env["HTTP_ACCEPT"]          = "*/*"
      env["GATEWAY_INTERFACE"]    = "CGI/1.2"
      env["SERVER_PORT"]          = req.serverPort.to_s
      env["QUERY_STRING"]         = req.queryString || ""
      env["SERVER_PROTOCOL"]      = "HTTP/1.1"
      env["rack.url_scheme"]      = "http" # only http is support
      env["SCRIPT_NAME"]          = ""
      env["REMOTE_ADDR"]          = req.getRemoteAddr()

      env["CONTENT_TYPE"]         = req.contentType || ""
      env["CONTENT_LENGTH"]       = req.contentLength.to_s

      # // m.put(URI, req.uri);
      # // m.put(ASYC_CHANNEL, req.channel);
      # // m.put(WEBSOCKET, req.isWebSocket);

      # // // key is already lower cased, required by ring spec
      # // m.put(HEADERS, PersistentArrayMap.create(req.headers));
      # // m.put(CONTENT_TYPE, req.contentType);
      # // m.put(CONTENT_LENGTH, req.contentLength);
      # // m.put(CHARACTER_ENCODING, req.charset);
      # // m.put(BODY, req.getBody());

      env
    end

    def run
      begin
        resp = handler.call(req_to_rack(req))
        if ! resp
          cb.run(HttpUtils.HttpEncode(404, Java::OrgHttpkit::HeaderMap.new(), nil));
        else
          status, headers, body = resp

          if ! body.is_a?(Java::OrgHttpkitServer::AsyncChannel)
            b = Java::OrgHttpkit::DynamicBytes.new(512)

            body.each do |chunk|
              b.append(chunk.to_s)
            end

            body = Java::JavaNio::ByteBuffer.wrap(b.get(), 0, b.length())

            headers = Java::OrgHttpkit::HeaderMap.camelCase(headers)
            if req.version == Java::OrgHttpkit::HttpVersion::HTTP_1_0 && req.isKeepAlive
              headers.put("Connection", "Keep-Alive")
            end
            cb.run(HttpUtils.HttpEncode(status.to_i, headers, body))
          end
        end
      rescue => e
        puts e.message
        puts e.backtrace
        cb.run(HttpUtils.HttpEncode(500, Java::OrgHttpkit::HeaderMap.new(), e.message))
        HttpUtils.printError(req.method + " " + req.uri, e);
      end
    end
  end

  class RackHandler < Java::OrgHttpkitServer::RingHandler

    field_reader :execs
    field_reader :handler

    def handle(*args)
      if args[0].is_a?(Java::OrgHttpkitServer::HttpRequest) && args[1].is_a?(Java::OrgHttpkitServer::RespCallback)
        handle_http(args[0], args[1])
      else
        handle_async(args[0], args[1])
      end
    end

    # void handle(HttpRequest request, RespCallback callback)
    def handle_http(request, callback)
      begin
        execs.submit( HttpKit::HttpHandler.new(request, callback, handler) )
      rescue java.util.concurrent.RejectedExecutionException => e
        HttpUtils.printError("increase :queue-size if this happens often", e);
        callback.run(HttpUtils.HttpEncode(503, Java::OrgHttpkit::HeaderMap.new(), "Server is overloaded, please try later"));
      end
    end

    # void handle(AsyncChannel channel, Frame frame)
    def handle_async(channel, frame)

    end

    # java_signature %Q{ @override public void clientClose(AsyncChannel channel, int status) }
    def client_close(channel, status)

    end


    # java_signature %Q{ @override void close() }
    def close

    end
  end

end
