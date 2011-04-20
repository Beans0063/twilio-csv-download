module Twilio
  class RestAccount
      def fetch(url, params, method=nil)
        if method && method == 'GET'
          url = build_get_uri(url, params)
        end
        #monkey patch here - must encode url to allow for greater than < or less than > in url
        uri = URI.parse(URI.encode(url))
        puts url

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        if method && method == 'GET'
          req = Net::HTTP::Get.new(uri.request_uri)
        elsif method && method == 'DELETE'
          req = Net::HTTP::Delete.new(uri.request_uri)
        elsif method && method == 'PUT'
          req = Net::HTTP::Put.new(uri.request_uri)
          req.set_form_data(params)
        else
          req = Net::HTTP::Post.new(uri.request_uri)
          req.set_form_data(params)
        end
        req.basic_auth(@id, @token)

        return http.request(req)
      end
    end
end
