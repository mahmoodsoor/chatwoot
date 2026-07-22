class ApplySoorBrandingToExistingInstallations < ActiveRecord::Migration[7.0]
  BRANDING_UPDATES = {
    'INSTALLATION_NAME' => { from: 'Chatwoot', to: 'SOOR' },
    'BRAND_NAME' => { from: 'Chatwoot', to: 'SOOR' },
    'BRAND_URL' => { from: 'https://www.chatwoot.com', to: 'https://bysoor.com/' },
    'WIDGET_BRAND_URL' => { from: 'https://www.chatwoot.com', to: 'https://bysoor.com/' },
    'TERMS_URL' => { from: 'https://www.chatwoot.com/terms-of-service', to: 'https://bysoor.com/terms-and-conditions/' },
    'PRIVACY_URL' => { from: 'https://www.chatwoot.com/privacy-policy', to: 'https://bysoor.com/privacy-policy/' },
    'LOGO_THUMBNAIL' => { from: '/brand-assets/logo_thumbnail.svg', to: '/brand-assets/logo_thumbnail.svg?v=soor-v4.16.0' },
    'LOGO' => { from: '/brand-assets/logo.svg', to: '/brand-assets/logo.svg?v=soor-v4.16.0' },
    'LOGO_DARK' => { from: '/brand-assets/logo_dark.svg', to: '/brand-assets/logo_dark.svg?v=soor-v4.16.0' }
  }.freeze

  def up
    BRANDING_UPDATES.each do |name, values|
      config = InstallationConfig.unscoped.find_by(name: name)
      next unless config&.value == values[:from]

      config.value = values[:to]
      config.save!
    end
  end

  def down
    BRANDING_UPDATES.each do |name, values|
      config = InstallationConfig.unscoped.find_by(name: name)
      next unless config&.value == values[:to]

      config.value = values[:from]
      config.save!
    end
  end
end
