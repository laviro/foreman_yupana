class ConvertObfuscationSettingsToParams < ActiveRecord::Migration[6.1]
  def change
    # Create the common parameters if they don't exist and set the default values to false
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_hostnames', value: false)
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_ips', value: false)

    # Copy the settings to the common parameters and remove the settings from the database
    # rubocop:disable Style/GuardClause
    if Setting.find_by(name: 'obfuscate_inventory_hostnames')&.value
      hostname_setting = CommonParameter.find_by(name: 'obfuscate_inventory_hostnames')
      hostname_setting.update!(value: Setting.find_by(name: 'obfuscate_inventory_hostnames')&.value)
      Setting.find_by(name: 'obfuscate_inventory_hostnames').destroy_all
    end

    if Setting.find_by(name: 'obfuscate_inventory_ips')&.value
      ip_setting = CommonParameter.find_by(name: 'obfuscate_inventory_ips')
      ip_setting.update!(value: Setting.find_by(name: 'obfuscate_inventory_ips')&.value)
      Setting.find_by(name: 'obfuscate_inventory_ips').destroy_all
    end
    # rubocop:enable Style/GuardClause
  end
end
