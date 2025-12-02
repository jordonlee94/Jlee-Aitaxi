fx_version 'cerulean'
game 'gta5'

author 'JLee-Gaming'
description 'QB-Core AI Taxi (v11) - confirmation modal, animated popups, anti-stuck'
version '11.0.0'

shared_script 'config.lua'

client_scripts {
    'client/client.lua'
}

server_scripts {
    '@qb-core/shared/locale.lua',
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/*'
}

dependencies {
    'qb-core'
}
