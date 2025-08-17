fx_version 'cerulean'
game 'gta5'

description 'qbx_ambulancejob'
repository 'https://github.com/Qbox-project/qbx_ambulancejob'
version '1.0.0'

-- Enable ox_lib JSON locale loader
ox_lib 'locale'

shared_scripts {
  '@ox_lib/init.lua',
  '@qbx_core/modules/lib.lua',
}

-- Order matters: main.lua defines helpers used by others (e.g., OnKeyPress)
client_scripts {
  '@qbx_core/modules/playerdata.lua',
  'client/main.lua',
  'client/hospital.lua',
  'client/job.lua',
  'client/laststand.lua',
  'client/setdownedstate.lua',
  'client/wounding.lua',
}

server_scripts {
  'server/hospital.lua',
  'server/main.lua',
}

-- JSON locales for ox_lib and config files used via require('config.*')
files {
  'locales/*.json',
  'config/client.lua',
  'config/server.lua',
  'config/shared.lua',
}

dependencies {
  'ox_lib',
  'qbx_core',
  'ox_inventory',
  'ox_target',
  'sleepless_interact',
  -- If you rely on these extras in your environment, keep them installed/enabled:
  -- 'cd_dispatch',
  -- 'fd_banking',
  -- 'ef_lib',
  -- 'ef_discordbot',
  -- 'ef_nexus',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
