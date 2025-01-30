require 'rest-client'

module ForemanRhCloud
  class CloudRequestForwarder
    include ForemanRhCloud::CloudRequest

    def forward_request(original_request, controller_name, branch_id, certs)
      forward_params = prepare_forward_params(original_request, branch_id)
      logger.debug("Request parameters for telemetry request: #{forward_params}")

      forward_payload = prepare_forward_payload(original_request, controller_name)

      logger.debug("User agent for telemetry is: #{http_user_agent original_request}")

      request_opts = prepare_request_opts(original_request, forward_payload, forward_params, certs)

      logger.debug("Sending request to: #{request_opts[:url]}")

      execute_cloud_request(request_opts)
    rescue RestClient::ExceptionWithResponse => error_response
      error_response.response
    end

    def prepare_request_opts(original_request, forward_payload, forward_params, certs)
      base_params = {
        method: original_request.method,
        payload: forward_payload,
        headers: original_headers(original_request).merge(
          {
            params: forward_params,
            user_agent: http_user_agent(original_request),
            content_type: original_request.media_type.presence || original_request.format.to_s,
          }
        ),
      }
      requested_url = original_request.original_fullpath.end_with?('/') ? original_request.path + '/' : original_request.path
      base_params.merge(path_params(requested_url, certs))
    end

    def prepare_forward_payload(original_request, controller_name)
      forward_payload = original_request.request_parameters[controller_name]

      forward_payload = original_request.raw_post.clone if (original_request.post? || original_request.patch?) && original_request.raw_post
      forward_payload = original_request.body.read if original_request.put?

      forward_payload = original_request.params.slice(:file, :metadata) if original_request.params[:file]

      # fix rails behaviour for http PATCH:
      forward_payload = forward_payload.to_json if original_request.format.json? && original_request.patch? && forward_payload && !forward_payload.is_a?(String)
      forward_payload
    end

    def prepare_forward_params(original_request, branch_id)
      forward_params = original_request.query_parameters
      if original_request.user_agent && !original_request.user_agent.include?('redhat_access_cfme')
        forward_params = forward_params.merge(:branch_id => branch_id)
      end

      forward_params
    end

    def path_params(request_path, certs)
      case request_path
      when platform_request?
        {
          url: ForemanRhCloud.cert_base_url + request_path.sub('/redhat_access/r/insights/platform', '/api'),
          ssl_client_cert: OpenSSL::X509::Certificate.new(certs[:cert]),
          ssl_client_key: OpenSSL::PKey.read(certs[:key]),
        }
      when connection_test_request?
        {
          url: ForemanRhCloud.cert_base_url + '/api/apicast-tests/ping',
          ssl_client_cert: OpenSSL::X509::Certificate.new(certs[:cert]),
          ssl_client_key: OpenSSL::PKey.read(certs[:key]),
        }
      else # Legacy insights API
        {
          url: ForemanRhCloud.legacy_insights_url + request_path.sub('/redhat_access/r/insights', '/r/insights'),
          ssl_client_cert: OpenSSL::X509::Certificate.new(certs[:cert]),
          ssl_client_key: OpenSSL::PKey.read(certs[:key]),
          ssl_ca_file: ForemanRhCloud.legacy_insights_ca,
        }
      end
    end

    def original_headers(original_request)
      headers = {
        if_none_match: original_request.if_none_match,
        if_modified_since: original_request.if_modified_since,
      }.compact

      logger.debug("Sending headers: #{headers}")
      headers
    end

    def platform_request?
      ->(request_path) { request_path.include? '/platform' }
    end

    def connection_test_request?
      ->(request_path) { request_path =~ /redhat_access\/r\/insights\/?$/ }
    end

    def prepare_forward_cloud_url(base_url, request_path)
      cloud_path = request_path.sub('/redhat_access/r/insights/platform/', '')
                               .sub('/redhat_access/r/insights/', '')

      "#{base_url}/api/#{cloud_path}"
    end

    def core_app_name
      BranchInfo.new.core_app_name
    end

    def core_app_version
      BranchInfo.new.core_app_version
    end

    def http_user_agent(original_request)
      "#{core_app_name}/#{core_app_version};#{ForemanRhCloud::Engine.engine_name}/#{ForemanRhCloud::VERSION};#{original_request.env['HTTP_USER_AGENT']}"
    end

    def logger
      Foreman::Logging.logger('app')
    end
  end
end
