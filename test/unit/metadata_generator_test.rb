require 'test_plugin_helper'

class MetadataGeneratorTest < ActiveSupport::TestCase
  setup do
    ForemanRhCloud.instance_variable_set(:@foreman_host, nil)
  end

  test 'generates an empty report' do
    @host = FactoryBot.create(:host, :managed)
    ForemanRhCloud.expects(:foreman_host_name).returns(@host.name)
    hostname = `uname -n`.chomp
    generator = ForemanInventoryUpload::Generators::Metadata.new

    json_str = generator.render do
    end
    actual = JSON.parse(json_str.join("\n"))
    assert_not_nil actual['report_id']
    assert_equal 'Satellite', actual['source']
    assert_equal hostname, actual['reporting_host_name']
    assert_not_nil (actual_metadata = actual['source_metadata'])
    assert_equal ForemanRhCloud::VERSION, actual_metadata['foreman_rh_cloud_version']
    assert_equal({}, actual['report_slices'])
  end

  test 'generates an empty report with hidden hostname and ip' do
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_ips', value: true)
    CommonParameter.find_or_create_by!(name: 'obfuscate_inventory_hostnames', value: true)
    @host = FactoryBot.create(:host, :managed)
    ForemanRhCloud.expects(:foreman_host_name).returns(@host.name)
    generator = ForemanInventoryUpload::Generators::Metadata.new

    json_str = generator.render do
    end
    actual = JSON.parse(json_str.join("\n"))
    assert_not_nil actual['report_id']
    assert_equal 'Satellite', actual['source']
    assert_not_nil (actual_metadata = actual['source_metadata'])
    assert_equal ForemanRhCloud::VERSION, actual_metadata['foreman_rh_cloud_version']
    assert_equal({}, actual['report_slices'])
  end

  test 'generates a report for a single slice' do
    @host = FactoryBot.create(:host, :managed)
    ForemanRhCloud.expects(:foreman_host_name).returns(@host.name)
    hostname = `uname -n`.chomp
    generator = ForemanInventoryUpload::Generators::Metadata.new

    json_str = generator.render do |gen|
      gen.add_slice('test_123', 1, true)
      gen.add_slice('test_1234', 2, false)
      gen.add_slice('test_12345', 3, false)
    end

    actual = JSON.parse(json_str.join("\n"))

    assert_not_nil actual['report_id']
    assert_equal 'Satellite', actual['source']
    assert_equal hostname, actual['reporting_host_name']
    assert_not_nil(slices = actual['report_slices'])
    assert_not_nil(slice = slices['test_123'])
    assert_equal 1, slice['number_hosts']
    assert_not_nil(slice = slices['test_1234'])
    assert_equal 2, slice['number_hosts']
    assert_not_nil(slice = slices['test_12345'])
    assert_equal 3, slice['number_hosts']
  end
end
