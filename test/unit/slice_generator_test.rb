require 'test_plugin_helper'

class SliceGeneratorTest < ActiveSupport::TestCase
  include KatelloLocationFix
  include CandlepinIsolation

  setup do
    User.current = User.find_by(login: 'secret_admin')

    env = FactoryBot.create(:katello_k_t_environment)
    cv = env.content_views << FactoryBot.create(:katello_content_view, organization: env.organization)

    location = FactoryBot.create(:location)

    @host = FactoryBot.create(
      :host,
      :redhat,
      :with_subscription,
      :with_content,
      content_view: cv.first,
      lifecycle_environment: env,
      organization: env.organization,
      location: location
    )

    @host.organization.pools << FactoryBot.create(
      :katello_pool,
      account_number: '1234',
      cp_id: 1,
      organization: env.organization,
      subscription: FactoryBot.create(:katello_subscription, organization_id: env.organization.id)
    )
    @host.interfaces.first.identifier = 'test_nic1'
    @host.interfaces.first.save!

    ForemanInventoryUpload::Generators::Queries.instance_variable_set(:@fact_names, nil)
  end

  def interesting_facts
    [
      'dmi::system::uuid',
      'virt::uuid',
      'cpu::cpu(s)',
      'cpu::cpu_socket(s)',
      'cpu::core(s)_per_socket',
      'memory::memtotal',
      'dmi::bios::vendor',
      'dmi::bios::version',
      'dmi::bios::relase_date',
      'uname::release',
      'lscpu::flags',
      'distribution::name',
      'distribution::version',
      'distribution::id',
      'virt::is_guest',
      'dmi::system::manufacturer',
      'dmi::system::product_name',
      'dmi::chassis::asset_tag',
      'insights_client::obfuscate_hostname_enabled',
      'insights_client::hostname',
      'insights_client::obfuscate_ip_enabled',
      'insights_client::ips',
      'insights_id',
    ]
  end

  def fact_names
    @fact_names ||= Hash[
      interesting_facts.map do |fact|
        [fact, FactoryBot.create(:fact_name, name: fact, type: 'Katello::RhsmFactName')]
      end
    ]
  end

  test 'generates a report for a single host' do
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_nil actual_host['ip_addresses']
    assert_nil actual_host['mac_addresses']
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_nil actual_system_profile['number_of_cpus']
    assert_nil actual_system_profile['number_of_sockets']
    assert_nil actual_system_profile['cores_per_socket']
    assert_nil actual_system_profile['system_memory_bytes']
    assert_nil actual_system_profile['os_release']
    assert_not_nil(actual_network_interfaces = actual_system_profile['network_interfaces'])
    assert_not_nil(actual_nic = actual_network_interfaces.first)
    refute actual_nic.key?('mtu')
    refute actual_nic.key?('mac_address')
    assert_equal 'test_nic1', actual_nic['name']
  end

  test 'hosts report fields should be present if fact exist' do
    FactoryBot.create(:fact_value, fact_name: fact_names['cpu::cpu(s)'], value: '4', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['cpu::cpu_socket(s)'], value: '2', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['cpu::core(s)_per_socket'], value: '1', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_equal 4, actual_system_profile['number_of_cpus']
    assert_equal 2, actual_system_profile['number_of_sockets']
    assert_equal 1, actual_system_profile['cores_per_socket']
  end

  test 'generates ip_address and mac_address fields' do
    nic = FactoryBot.build(:nic_managed)
    nic.attrs['mtu'] = '1500'
    @host.interfaces << nic
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.interfaces.where.not(ip: nil).first.ip, actual_host['ip_addresses'].first
    assert_equal @host.interfaces.where.not(mac: nil).first.mac, actual_host['mac_addresses'].first
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'generates nic fields' do
    empty_nic = FactoryBot.build(:nic_managed, ip6: '', identifier: 'empty_nic')
    @host.interfaces << empty_nic
    ip6 = Array.new(4) { '%x' % rand(16**4) }.join(':') + '::' + '5'
    nic = FactoryBot.build(:nic_managed, ip6: ip6, identifier: 'good_nic')
    nic.attrs['mtu'] = '1500'
    @host.interfaces << nic
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.interfaces.where.not(ip: nil).first.ip, actual_host['ip_addresses'].first
    assert_equal @host.interfaces.where.not(mac: nil).first.mac, actual_host['mac_addresses'].first
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_not_nil(actual_network_interfaces = actual_system_profile['network_interfaces'])
    assert_not_nil(actual_empty_nic = actual_network_interfaces.find { |actual_nic| actual_nic['name'] == 'empty_nic' })
    assert actual_empty_nic['ipv6_addresses'].empty?
    assert_not_nil(actual_nic = actual_network_interfaces.find { |actual_nic| actual_nic['name'] == 'good_nic' })
    assert_equal nic.ip, actual_nic['ipv4_addresses'].first
    assert_equal nic.ip6, actual_nic['ipv6_addresses'].first
    assert_equal 1500, actual_nic['mtu']
    assert_equal nic.mac, actual_nic['mac_address']
    assert_equal nic.identifier, actual_nic['name']
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'skips nameless nics' do
    ip6 = Array.new(4) { '%x' % rand(16**4) }.join(':') + '::' + '5'
    nic = FactoryBot.build(:nic_managed, ip6: ip6, identifier: '')
    nic.attrs['mtu'] = '1500'
    @host.interfaces << nic
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.interfaces.where.not(ip: nil).first.ip, actual_host['ip_addresses'].first
    assert_equal @host.interfaces.where.not(mac: nil).first.mac, actual_host['mac_addresses'].first
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_not_nil(actual_network_interfaces = actual_system_profile['network_interfaces'])
    assert_nil actual_network_interfaces.find { |actual_nic| actual_nic['name'].empty? }
  end

  test 'generates obfuscated ip_address fields without inisghts-client' do
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_ips', value: true)

    @host.interfaces << FactoryBot.build(:nic_managed)
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal '10.230.230.1', actual_host['ip_addresses'].first
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_not_nil(actual_network_interfaces = actual_system_profile['network_interfaces'])
    assert_not_nil(actual_nic = actual_network_interfaces.first)
    assert_equal '10.230.230.1', actual_nic['ipv4_addresses'].first
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'generates obfuscated ip_address fields with inisghts-client' do
    nic = FactoryBot.build(:nic_managed)
    @host.interfaces << nic

    FactoryBot.create(:fact_value, fact_name: fact_names['insights_client::obfuscate_ip_enabled'], value: 'true', host: @host)
    FactoryBot.create(
      :fact_value,
      fact_name: fact_names['insights_client::ips'],
      value: "[{\"obfuscated\": \"10.230.230.100\", \"original\": \"#{nic.ip}\"}]",
      host: @host
    )

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal '10.230.230.100', actual_host['ip_addresses'].first
    assert_not_nil(actual_system_profile = actual_host['system_profile'])
    assert_not_nil(actual_network_interfaces = actual_system_profile['network_interfaces'])
    assert_not_nil(actual_nic = actual_network_interfaces.first)
    assert_equal '10.230.230.100', actual_nic['ipv4_addresses'].first
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'obfuscates fqdn when instructed by insights-client' do
    FactoryBot.create(:fact_value, fact_name: fact_names['insights_client::obfuscate_hostname_enabled'], value: 'true', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['insights_client::hostname'], value: 'obfuscated_name', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal 'obfuscated_name', actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_not_nil(actual_facts = actual_host['facts'].first['facts'])
    assert_equal true, actual_facts['is_hostname_obfuscated']
    assert_equal 1, generator.hosts_count
  end

  test 'obfuscates fqdn when setting set' do
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_hostnames', value: true)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    obfuscated_fqdn = Digest::SHA1.hexdigest(@host.fqdn) + '.example.com'

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal obfuscated_fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_not_nil(actual_facts = actual_host['facts'].first['facts'])
    assert_equal true, actual_facts['is_hostname_obfuscated']
    assert_equal 1, generator.hosts_count
  end

  test 'does not obfuscate fqdn when insights-client sets to false' do
    FactoryBot.create(:fact_value, fact_name: fact_names['insights_client::obfuscate_hostname_enabled'], value: 'false', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['insights_client::hostname'], value: 'obfuscated_name', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_not_nil(actual_facts = actual_host['facts'].first['facts'])
    assert_equal false, actual_facts['is_hostname_obfuscated']
    assert_equal 1, generator.hosts_count
  end

  test 'generates a report with satellite facts' do
    hostgroup = FactoryBot.create(:hostgroup, name: 'Special"name')
    # Don't try to update CP in tests
    Katello::Resources::Candlepin::Consumer.stubs(:update)
    # Don't try update facts for the host
    Katello::Host::SubscriptionFacet.stubs(:update_facts)

    @host.hostgroup = hostgroup
    @host.save!

    ForemanInventoryUpload::Generators::Tags.any_instance.expects(:generate_parameters).returns(
      [
        ['bool_param', true],
        ['int_param', 1],
      ]
    )

    Foreman.expects(:instance_id).twice.returns('satellite-id')
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    facts = actual['hosts'].first['facts'].first
    assert_equal 'satellite', facts['namespace']
    satellite_facts = facts['facts']
    assert_equal 'satellite-id', satellite_facts['satellite_instance_id']
    assert_equal @host.organization_id, satellite_facts['organization_id']

    actual_host = actual['hosts'].first
    assert_tag('satellite-id', actual_host, 'satellite_instance_id')
    assert_tag(@host.organization_id.to_s, actual_host, 'organization_id')
    assert_tag(@host.content_views.first.name, actual_host, 'content_view')
    assert_tag(@host.location.name, actual_host, 'location')
    assert_tag(@host.organization.name, actual_host, 'organization')
    assert_tag(@host.hostgroup.name, actual_host, 'hostgroup')
    assert_tag('true', actual_host, 'bool_param', 'satellite_parameter')
    assert_tag('1', actual_host, 'int_param', 'satellite_parameter')

    assert_equal false, satellite_facts['is_hostname_obfuscated']

    version = satellite_facts['satellite_version']
    if defined?(ForemanThemeSatellite)
      assert_equal ForemanThemeSatellite::SATELLITE_VERSION, version
    else
      assert_nil version
    end
  end

  test 'generates a report for a host with hypervisor' do
    hypervisor_host = FactoryBot.create(
      :host,
      :with_subscription,
      :with_content,
      content_view: @host.content_views.first,
      lifecycle_environment: @host.lifecycle_environments.first,
      organization: @host.organization
    )

    @host.subscription_facet.hypervisor_host = hypervisor_host
    @host.subscription_facet.save!

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_not_nil(host_facts = actual_host['facts']&.first)
    assert_equal 'satellite', host_facts['namespace']
    assert_not_nil(fact_values = host_facts['facts'])
    assert_equal hypervisor_host.name, fact_values['virtual_host_name']
    assert_equal hypervisor_host.subscription_facet.uuid, fact_values['virtual_host_uuid']
  end

  test 'generates a report with system purpose' do
    @host.subscription_facet.purpose_usage = 'test_usage'
    @host.subscription_facet.purpose_role = 'test_role'
    @host.subscription_facet.service_level = 'test_sla'
    @host.subscription_facet.save!

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_not_nil(host_facts = actual_host['facts']&.first)
    assert_equal 'satellite', host_facts['namespace']
    assert_not_nil(fact_values = host_facts['facts'])
    assert_equal 'test_usage', fact_values['system_purpose_usage']
    assert_equal 'test_role', fact_values['system_purpose_role']
    assert_equal 'test_sla', fact_values['system_purpose_sla']
  end

  test 'generates a report for a golden ticket' do
    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch) do |generator|
      generator.stubs(:golden_ticket?).returns(true)
    end

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'skips hosts without subscription' do
    a_host = FactoryBot.create(
      :host,
      organization: @host.organization
    )

    # make a_host last
    batch = Host.where(id: [@host.id, a_host.id]).order(:name).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_equal @host.fqdn, actual_host['fqdn']
    assert_equal '1234', actual_host['account']
    assert_equal 1, generator.hosts_count
  end

  test 'include also hosts with non-redhat OS' do
    os = @host.operatingsystem
    os.name = 'Centos'
    os.save!

    # make a_host last
    batch = ForemanInventoryUpload::Generators::Queries.for_org(@host.organization_id).first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_equal 1, generator.hosts_count
  end

  test 'excludes hosts with host_registration_insights set to false' do
    @host.host_parameters << HostParameter.create(
      name: 'host_registration_insights',
      value: "false",
      parameter_type: 'boolean'
    )

    count = ForemanInventoryUpload::Generators::Queries.for_org(@host.organization_id).count

    assert_equal 0, count
  end

  test 'shows system_memory_bytes in bytes' do
    FactoryBot.create(:fact_value, fact_name: fact_names['memory::memtotal'], value: '1', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 1024, actual_profile['system_memory_bytes']
  end

  test 'reports an account for hosts with multiple pools' do
    new_org = FactoryBot.create(:organization)
    first_pool = FactoryBot.create(
      :katello_pool,
      account_number: '5678',
      cp_id: 2,
      organization: new_org,
      subscription: FactoryBot.create(:katello_subscription, organization_id: new_org.id)
    )
    second_pool = FactoryBot.create(
      :katello_pool,
      account_number: '9012',
      cp_id: 3,
      organization: new_org,
      subscription: FactoryBot.create(:katello_subscription, organization_id: new_org.id)
    )
    new_org.pools << first_pool
    new_org.pools << second_pool

    another_host = FactoryBot.create(
      :host,
      :with_subscription,
      :with_content,
      content_view: @host.content_views.first,
      lifecycle_environment: @host.lifecycle_environments.first,
      organization: new_org
    )

    batch = Host.where(id: another_host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_host['account'])
    assert_not_empty(actual_host['account'])
  end

  test 'Generates os_release with version and id' do
    FactoryBot.create(:fact_value, fact_name: fact_names['distribution::name'], value: 'Red Hat Test Linux', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['distribution::version'], value: '7.1', host: @host)
    FactoryBot.create(:fact_value, fact_name: fact_names['distribution::id'], value: 'TestId', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'Red Hat Test Linux 7.1 (TestId)', actual_profile['os_release']
  end

  test 'sets infrastructure_type to "virtual" based on virt.is_guest fact' do
    FactoryBot.create(:fact_value, fact_name: fact_names['virt::is_guest'], value: true, host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'virtual', actual_profile['infrastructure_type']
  end

  test 'sets infrastructure_type to "physical" based on virt.is_guest fact' do
    FactoryBot.create(:fact_value, fact_name: fact_names['virt::is_guest'], value: false, host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'physical', actual_profile['infrastructure_type']
  end

  test 'Identifies Amazon cloud provider' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::bios::version'], value: 'Test Amazon version', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'aws', actual_profile['cloud_provider']
  end

  test 'Identifies Google cloud provider' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::bios::version'], value: 'Test Google version', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'gcp', actual_profile['cloud_provider']
  end

  test 'Identifies Azure cloud provider' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::chassis::asset_tag'], value: '7783-7084-3265-9085-8269-3286-77', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'azure', actual_profile['cloud_provider']
  end

  test 'Identifies Alibaba cloud provider via manufacturer' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::system::manufacturer'], value: 'Test Alibaba Cloud version', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'alibaba', actual_profile['cloud_provider']
  end

  test 'Identifies Alibaba cloud provider via product name' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::system::product_name'], value: 'Test Alibaba Cloud ECS product', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_equal 'alibaba', actual_profile['cloud_provider']
  end

  test 'include packages installed in the report' do
    Setting[:exclude_installed_packages] = false
    installed_package = ::Katello::InstalledPackage.create(name: 'test-package', nvrea: 'test-package-1.0.x86_64', nvra: 'test-package-1.0.x86_64')

    another_host = FactoryBot.create(
      :host,
      :with_subscription,
      :with_content,
      content_view: @host.content_views.first,
      lifecycle_environment: @host.lifecycle_environments.first,
      organization: @host.organization,
      installed_packages: [installed_package]
    )

    batch = Host.where(id: another_host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil(actual_profile = actual_host['system_profile'])
    assert_not_nil(actual_profile['installed_packages'])
  end

  test 'omits malformed bios_uuid field' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::system::uuid'], value: 'test value', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_nil actual_host['bios_uuid']
  end

  test 'passes valid bios_uuid field' do
    FactoryBot.create(:fact_value, fact_name: fact_names['dmi::system::uuid'], value: 'D30B0B42-7824-2635-C62D-491394DE43F7', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil actual_host['bios_uuid']
  end

  test 'passes valid insights_id field' do
    FactoryBot.create(:fact_value, fact_name: fact_names['insights_id'], value: 'D30B0B42-7824-2635-C62D-491394DE43F7', host: @host)

    batch = Host.where(id: @host.id).in_batches.first
    generator = create_generator(batch)

    json_str = generator.render
    actual = JSON.parse(json_str.join("\n"))

    assert_equal '00000000-0000-0000-0000-000000000000', actual['report_slice_id']
    assert_not_nil(actual_host = actual['hosts'].first)
    assert_not_nil actual_host['insights_id']
  end

  private

  def create_generator(batch, name = '00000000-0000-0000-0000-000000000000')
    generator = ForemanInventoryUpload::Generators::Slice.new(batch, [], name)
    if block_given?
      yield(generator)
    else
      generator.stubs(:golden_ticket?).returns(false)
    end
    generator
  end

  def assert_tag(expected_value, host, tag_id, namespace = 'satellite')
    actual_tag = host['tags'].find { |tag| tag['namespace'] == namespace && tag['key'] == tag_id }
    assert_not_nil actual_tag
    assert_equal expected_value, actual_tag['value']
  end
end
