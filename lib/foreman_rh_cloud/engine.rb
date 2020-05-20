require 'katello'
require 'redhat_access'

module ForemanRhCloud
  class Engine < ::Rails::Engine
    engine_name 'foreman_rh_cloud'

    initializer 'foreman_rh_cloud.load_default_settings', :before => :load_config_initializers do
      require_dependency File.expand_path('../../app/models/setting/rh_cloud.rb', __dir__)
    end

    config.autoload_paths += Dir["#{config.root}/app/controllers/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/helpers/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/models/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/overrides"]
    config.autoload_paths += Dir["#{config.root}/lib"]

    config.eager_load_paths += Dir["#{config.root}/lib"]

    # Add any db migrations
    initializer 'foreman_rh_cloud.load_app_instance_data' do |app|
      ForemanRhCloud::Engine.paths['db/migrate'].existent.each do |path|
        app.config.paths['db/migrate'] << path
      end
    end

    initializer 'foreman_rh_cloud.register_plugin', :before => :finisher_hook do |_app|
      Foreman::Plugin.register :foreman_rh_cloud do
        requires_foreman '> 1.24'

        # Add permissions
        security_block :foreman_rh_cloud do
          permission :generate_foreman_rh_cloud, :'foreman_inventory_uploads/reports' => [:generate]
          permission :view_foreman_rh_cloud, :'foreman_inventory_uploads/accounts' => [:index]
          permission :view_foreman_rh_cloud, :'foreman_inventory_uploads/reports' => [:last]
          permission :view_foreman_rh_cloud, :'foreman_inventory_uploads/uploads' => [:auto_upload]
          permission :view_foreman_rh_cloud, :'foreman_inventory_uploads/uploads' => [:download_file]
          permission :view_foreman_rh_cloud, :'foreman_inventory_uploads/uploads' => [:last]
          permission :view_foreman_rh_cloud, :'foreman_rh_cloud/react' => [:inventory_upload]
        end

        plugin_permissions = [:view_foreman_rh_cloud, :generate_foreman_rh_cloud]

        role 'ForemanRhCloud', plugin_permissions, 'Role granting permissions to view the hosts inventory,
                                                    generate a report, upload it to the cloud and download it locally'

        add_permissions_to_default_roles 'Organization admin' => plugin_permissions,
                                         'Manager' => plugin_permissions,
                                         'System admin' => plugin_permissions

        # Adding a sub menu after hosts menu
        sub_menu :top_menu, :foreman_rh_cloud, :caption => N_('RH Cloud'), :icon => 'fa fa-cloud-upload' do
          menu :top_menu, :level1, :caption => N_('Inventory Upload'), :url_hash => { controller: :'foreman_rh_cloud/react', :action => :inventory_upload}
        end
      end
    end

    initializer "foreman_rh_cloud.set_dynflow.config.on_init", :before => :finisher_hook do |_app|
      unless Rails.env.test?
        ForemanTasks.dynflow.config.on_init do |world|
          ForemanInventoryUpload::Async::GenerateAllReportsJob.spawn_if_missing(world)
        end
      end
    end

    rake_tasks do
      Rake::Task['db:seed'].enhance do
        ForemanRhCloud::Engine.load_seed
      end
    end

    initializer 'foreman_rh_cloud.register_gettext', after: :load_config_initializers do |_app|
      locale_dir = File.join(File.expand_path('../..', __dir__), 'locale')
      locale_domain = 'foreman_rh_cloud'
      Foreman::Gettext::Support.add_text_domain locale_domain, locale_dir
    end
  end
end
