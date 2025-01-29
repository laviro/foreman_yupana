require 'json'

module ForemanInventoryUpload
  module Generators
    module FactHelpers
      extend ActiveSupport::Concern

      CLOUD_AMAZON = 'aws'
      CLOUD_GOOGLE = 'gcp'
      CLOUD_AZURE = 'azure'
      CLOUD_ALIBABA = 'alibaba'

      UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

      def fact_value(host, fact_name)
        value_record = host.fact_values.find do |fact_value|
          fact_value.fact_name_id == ForemanInventoryUpload::Generators::Queries.fact_names[fact_name]
        end
        value_record&.value
      end

      def kilobytes_to_bytes(kilobytes)
        kilobytes * 1024
      end

      def account_id(organization)
        @organization_accounts ||= {}
        @organization_accounts[organization.id] ||= organization.pools.where.not(account_number: nil).pluck(:account_number).first
      end

      def golden_ticket?(organization)
        result = organization.try(:golden_ticket?)
        result = organization.content_access_mode == 'org_environment' if result.nil?

        @organization_golden_tickets ||= {}
        @organization_golden_tickets[organization.id] ||= result
      end

      def cloud_provider(host)
        bios_version = fact_value(host, 'dmi::bios::version')

        if bios_version
          return CLOUD_AMAZON if bios_version.downcase['amazon']
          return CLOUD_GOOGLE if bios_version.downcase['google']
        end

        chassis_asset_tag = fact_value(host, 'dmi::chassis::asset_tag')
        return CLOUD_AZURE if chassis_asset_tag && chassis_asset_tag['7783-7084-3265-9085-8269-3286-77']

        system_manufacturer = fact_value(host, 'dmi::system::manufacturer')
        return CLOUD_ALIBABA if system_manufacturer && system_manufacturer.downcase['alibaba cloud']

        product_name = fact_value(host, 'dmi::system::product_name')
        return CLOUD_ALIBABA if product_name && product_name.downcase['alibaba cloud ecs']

        nil
      end

      def obfuscate_hostname?(host)
        insights_client_setting = fact_value(host, 'insights_client::obfuscate_hostname_enabled')
        insights_client_setting = ActiveModel::Type::Boolean.new.cast(insights_client_setting)
        return insights_client_setting unless insights_client_setting.nil?

        CommonParameter.find_by(name: 'obfuscate_inventory_hostnames')&.value
      end

      def fqdn(host)
        return host.fqdn unless obfuscate_hostname?(host)

        fact_value(host, 'insights_client::hostname') || obfuscate_fqdn(host.fqdn)
      end

      def obfuscate_fqdn(fqdn)
        "#{Digest::SHA1.hexdigest(fqdn)}.example.com"
      end

      def obfuscate_ips?(host)
        insights_client_setting = fact_value(host, 'insights_client::obfuscate_ip_enabled')
        insights_client_setting = ActiveModel::Type::Boolean.new.cast(insights_client_setting)
        return insights_client_setting unless insights_client_setting.nil?

        CommonParameter.find_by(name: 'obfuscate_inventory_ips')&.value
      end

      def host_ips(host)
        return obfuscated_ips(host) if obfuscate_ips?(host)

        # return a pass through proxy hash in case no obfuscation needed
        Hash.new { |h, k| k }
      end

      def obfuscated_ips(host)
        insights_client_ips = JSON.parse(fact_value(host, 'insights_client::ips') || '[]')

        obfuscated_ips = Hash[
          insights_client_ips.map { |ip_record| [ip_record['original'], ip_record['obfuscated']] }
        ]

        obfuscated_ips.default_proc = proc do |hash, key|
          hash[key] = obfuscate_ip(key, hash)
        end

        obfuscated_ips
      end

      def obfuscate_ip(ip, ips_dict)
        max_obfuscated = ips_dict.values.map { |v| IPAddr.new(v).to_i }.max || IPAddr.new('10.230.230.0').to_i

        IPAddr.new(max_obfuscated + 1, Socket::AF_INET).to_s
      end

      def hostname_match
        bash_hostname = `uname -n`.chomp
        foreman_hostname = ForemanRhCloud.foreman_host&.name
        if bash_hostname == foreman_hostname
          fqdn(ForemanRhCloud.foreman_host)
        elsif CommonParameter.find_by(name: 'obfuscate_inventory_hostnames')&.value
          obfuscate_fqdn(bash_hostname)
        else
          bash_hostname
        end
      end

      def bios_uuid(host)
        value = fact_value(host, 'dmi::system::uuid') || ''
        uuid_value(value)
      end

      def uuid_value(value)
        uuid_match = UUID_REGEX.match(value)
        uuid_match&.to_s
      end

      def uuid_value!(value)
        uuid = uuid_value(value)
        raise Foreman::Exception.new(N_('Value %{value} is not a valid UUID') % { value: value }) if value && uuid.empty?

        uuid
      end
    end
  end
end
