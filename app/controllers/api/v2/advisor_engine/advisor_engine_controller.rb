module Api
  module V2
    module AdvisorEngine
      class AdvisorEngineController < ::Api::V2::BaseController
        include ::Api::Version2
        include Foreman::Controller::SmartProxyAuth
        include ::Foreman::Controller::FilterParameters

        filter_parameters :payload
        add_smart_proxy_filters [:host_details, :upload_hits]

        api :GET, "/advisor_engine/host_details", N_('Fetch Insights-related host details')
        param :host_uuids, Array, required: true, desc: N_('List of host UUIDs')
        def host_details
          uuids = params.require(:host_uuids)
          @hosts = ::Host.joins(:insights).where(:insights => { :uuid => uuids })
          if @hosts.empty?
            render json: { error: 'No hosts found for the given UUIDs' }, status: :not_found
          else
            respond_to do |format|
              format.json { render 'api/v2/advisor_engine/host_details' }
            end
          end
        end

        api :PATCH, "/advisor_engine/upload_hits", N_("Upload hits from iop-advisor-engine")
        param :host_name, String, required: true
        param :host_uuid, String

        param :payload, Hash, :desc => N_("iop payload including resolutions, rules, hits") do
          param :resolutions, Array, :desc => N_("upload resolutions related to the hits") do
            param :rule_id, String,  :desc => N_("rule id"), :required => true
            param :description, String, :desc => N_("resolution description")
            param :needs_reboot, :bool, :desc => N_("Whether the resolution requires reboot")
            param :resolution_risk, String, :desc => N_("resolution risk")
            param :resolution_type, String, :desc => N_("type")
          end

          param :rules, Array, :desc => N_("Upload rules related to the hits") do
            param :rule_id, String, :desc => N_("rule id"), :required => true
            param :description, String, :desc => N_("rule description")
            param :category_name, String, :desc => N_("category name")
            param :impact_name, String, :desc => N_("impact name")
            param :summary, String, :desc => N_("summary")
            param :generic, String, :desc => N_("generic")
            param :reason, String, :desc => N_("reason")
            param :total_risk, :number, :desc => N_("total risk")
            param :reboot_required, :bool, :desc => N_("reboot required")
            param :more_info, String, :desc => N_("more info")
            param :rating, :number, :desc => N_("rating")
          end

          param :hits, Array, :desc => N_("Upload hits information") do
            param :rule_id, String, :desc => N_("rule id"), :required => true
            param :title, String, :desc => N_("rule title")
            param :solution_url, String, :desc => N_("solution url")
            param :total_risk, :number, :desc => N_("total risk")
            param :likelihood, :number, :desc => N_("likelihood number")
            param :publish_date, String, :desc => N_("publish date (YYYY-MM-DD)")
            param :results_url, String, :desc => N_("result url")
          end
          param :details, String, :desc => N_("upload hits details json")
        end

        def upload_hits
          host = Host.find_by(name: params.require(:host_name))
          if host.blank?
            render json: { error: 'No host found for the given host name' }, status: :not_found
          else
            hits_uploader = ForemanRhCloud::HitsUploader.new(host: host, payload: payload_params.to_h, uuid: params[:host_uuid])
            hits_uploader.upload!
            render json: {
              action_status: 'success',
            }, status: :ok
          end
        end

        def payload_params
          params.require(:payload).permit(
            :details,
            {
              resolutions: [
                :rule_id, :description, :needs_reboot, :resolution_risk, :resolution_type
              ],
              rules: [
                :rule_id, :description, :category_name, :impact_name, :summary, :generic,
                :reason, :total_risk, :reboot_required, :more_info, :rating
              ],
              hits: [
                :rule_id, :title, :solution_url, :total_risk, :likelihood, :publish_date, :results_url
              ],
            }
          )
        end
      end
    end
  end
end
