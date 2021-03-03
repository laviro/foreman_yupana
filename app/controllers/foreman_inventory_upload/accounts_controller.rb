module ForemanInventoryUpload
  class AccountsController < ::ApplicationController
    def index
      organizations = User.current.my_organizations
      labels = organizations.pluck(:id, :name)

      accounts = Hash[
        labels.map do |id, label|
          generate_report_status = status_for(id, ForemanInventoryUpload::Async::GenerateReportJob)
          upload_report_status = status_for(id, ForemanInventoryUpload::Async::UploadReportJob)

          [
            label,
            {
              generate_report_status: generate_report_status,
              upload_report_status: upload_report_status,
              id: id,
            },
          ]
        end
      ]

      render json: {
        autoUploadEnabled: Setting[:allow_auto_inventory_upload],
        hostObfuscationEnabled: Setting[:obfuscate_inventory_hostnames],
        ipsObfuscationEnabled: Setting[:obfuscate_inventory_ips],
        cloudToken: Setting[:rh_cloud_token],
        excludePackages: Setting[:exclude_installed_packages],
        accounts: accounts,
      }, status: :ok
    end

    private

    def status_for(label, job_class)
      label = job_class.output_label(label)
      ForemanInventoryUpload::Async::ProgressOutput.get(label)&.status
    end
  end
end
