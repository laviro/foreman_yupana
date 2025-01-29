module ForemanInventoryUpload
  class UploadsSettingsController < ::ApplicationController
    def index
      render json: {
        autoUploadEnabled: Setting[:allow_auto_inventory_upload],
        excludePackagesEnabled: Setting[:exclude_installed_packages],
        allowAutoInsightsMismatchDelete: Setting[:allow_auto_insights_mismatch_delete],
        CloudConnectorStatus: ForemanInventoryUpload::UploadsSettingsController.cloud_connector_status,
        lastSyncTask: last_successful_inventory_sync_task,
      }, status: :ok
    end

    def set_advanced_setting
      Setting[params.require(:setting)] = ActiveModel::Type::Boolean.new.cast(params.require(:value))
      index
    end

    def self.cloud_connector_status
      cloud_connector = ForemanRhCloud::CloudConnector.new
      job = cloud_connector&.latest_job
      return nil unless job
      { id: job.id, task: ForemanTasks::Task.where(:id => job.task_id).first }
    end

    def last_successful_inventory_sync_task
      task = ForemanTasks::Task.where(label: 'InventorySync::Async::InventoryFullSync', result: 'success')
                        .reorder('ended_at desc').first
      return nil unless task
      { output: task.output, endedAt: task.ended_at }
    end
  end
end
