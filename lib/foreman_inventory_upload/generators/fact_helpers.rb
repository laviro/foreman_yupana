require 'json'

module ForemanInventoryUpload
  module Generators
    module FactHelpers
      extend ActiveSupport::Concern

      CLOUD_AMAZON = 'aws'
      CLOUD_GOOGLE = 'google'
      CLOUD_AZURE = 'azure'
      CLOUD_ALIBABA = 'alibaba'

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

        Setting[:obfuscate_inventory_hostnames]
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

        Setting[:obfuscate_inventory_ips]
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
        "10.230.230.#{ips_dict.count + 1}"
      end
    end
  end
end
