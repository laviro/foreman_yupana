import { translate as __ } from 'foremanReact/common/I18n';

export const settingsDict = {
  autoUploadEnabled: {
    name: 'allow_auto_inventory_upload',
    label: __('Automatic inventory upload'),
    tooltip: __(
      'Enable automatic upload of your hosts inventory to the Red Hat cloud'
    ),
  },
  excludePackagesEnabled: {
    name: 'exclude_installed_packages',
    label: __('Exclude installed Packages'),
    tooltip: __(
      'Exclude installed packages from being uploaded to the Red Hat cloud'
    ),
  },
  allowAutoInsightsMismatchDelete: {
    name: 'allow_auto_insights_mismatch_delete',
    label: __('Automatic mismatch deletion'),
    tooltip: __(
      'Enable automatic deletion of mismatched host records from the Red Hat cloud'
    ),
  },
};
