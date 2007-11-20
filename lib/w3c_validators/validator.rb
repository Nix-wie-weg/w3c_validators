require 'cgi'
require 'net/http'
require 'uri'
require 'rexml/document'

require 'w3c_validators/exceptions'
require 'w3c_validators/constants'
require 'w3c_validators/results'
require 'w3c_validators/message'

module W3CValidators
  # Base class for MarkupValidator and FeedValidator.
  class Validator
    USER_AGENT                = 'Ruby W3C Validators/0.9 (http://code.dunae.ca/w3c_validators/)'
    VERSION                   = '0.9'
    HEAD_STATUS_HEADER        = 'X-W3C-Validator-Status'
    HEAD_ERROR_COUNT_HEADER   = 'X-W3C-Validator-Errors'
    SOAP_OUTPUT_PARAM         = 'soap12'

    attr_reader :results, :validator_uri

    # Create a new instance of the Validator.
    def initialize(options = {})
      @options = options
    end

  protected
    # Perform a validation request.
    #
    # +request_mode+ must be either <tt>:get</tt>, <tt>:head</tt> or <tt>:post</tt>.
    #
    # Returns Net::HTTPResponse.
    def send_request(options, request_mode = :get)
      response = nil
      results = nil

      Net::HTTP.start(@validator_uri.host, @validator_uri.port) do |http|
        case request_mode
          when :head
            # perform a HEAD request
            raise ArgumentError, "a URI must be provided for HEAD requests." unless options[:uri]
            query = create_query_string_data(options)
            response = http.request_head(@validator_uri.path + '?' + query)
          when :get 
            # send a GET request
            query = create_query_string_data(options)          
            response = http.get(@validator_uri.path + '?' + query)
          when :post
            # send a multipart form request
            query, boundary = create_multipart_data(options)
            response = http.post2(@validator_uri.path, query, "Content-type" => "multipart/form-data; boundary=" + boundary)
          else
            raise ArgumentError, "request_mode must be either :get, :head or :post"
        end
      end

      response.value
      return response

      rescue Exception => e
        handle_exception e
    end

    def create_multipart_data(options) # :nodoc:
      boundary = '349832898984244898448024464570528145'
      params = []
      if options[:uploaded_file]
        filename = options[:file_path] ||= 'temp.html'
        content = options[:uploaded_file]
        params << "Content-Disposition: form-data; name=\"uploaded_file\"; filename=\"#{filename}\"\r\n" + "Content-Type: text/html\r\n" + "\r\n" + "#{content}\r\n"
        options.delete(:uploaded_file)
        options.delete(:file_path)
      end

      options.each do |key, value|
        if value
          params << "Content-Disposition: form-data; name=\"#{CGI::escape(key.to_s)}\"\r\n" + "\r\n" + "#{value}\r\n"
        end
      end

      multipart_query = params.collect {|p| '--' + boundary + "\r\n" + p}.join('') + "--" + boundary + "--\r\n" 

      [multipart_query, boundary]
    end

    def create_query_string_data(options) # :nodoc:
      qs = ''
      options.each do |key, value| 
        if value
          qs += "#{key}=" + CGI::escape(value.to_s) + "&"
        end
      end
      qs
    end

    def read_local_file(file_path) # :nodoc:
      fh = File.new(file_path, 'r+')
      src = fh.read
      fh.close
      src
    end

  private
    #--
    # Big thanks to ara.t.howard and Joel VanderWerf on Ruby-Talk for the exception handling help.
    #++
    def handle_exception(e, msg = '') # :nodoc:
      case e      
        when Net::HTTPServerException, SocketError
          msg = "unable to connect to the validator at #{@validator_uri} (response was #{e.message})."
          raise ValidatorUnavailable, msg, caller
        when REXML::ParseException
          msg = "unable to parse the response from the validator."
          raise ParsingError, msg, caller
        else
          raise e
      end

      if e.respond_to?(:error_handler_before)
        fcall(e, :error_handler_before, self)
      end

      if e.respond_to?(:error_handler_instead)
        fcall(e, :error_handler_instead, self)
      else
        if e.respond_to? :status
          exit_status(( e.status ))
        end

        if SystemExit === e
          stderr.puts e.message unless(SystemExit === e and e.message.to_s == 'exit') ### avoids double message for abort('message')
        end
      end

      if e.respond_to?(:error_handler_after)
        fcall(e, :error_handler_after, self)
      end

      exit_status(( exit_failure )) if exit_status == exit_success
      exit_status(( Integer(exit_status) rescue(exit_status ? 0 : 1) ))
      exit exit_status
    end 
  end
end