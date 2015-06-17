fs = require 'fs'
yaml = require 'yamljs'

shell = require 'shelljs'
shell.config.fatal = true
shell.config.silent = true

class RunError extends Error
    # no idea why it won't pass on the message if I define it as
    # constructor: -> super
    constructor: (@message) -> super
    exit_code: 1

global.RunError = RunError

if process.env.MTS_DEBUG?.length
    console.debug = console.log
else
    console.debug = ->

class MeteorApp
    constructor: (@root, extra_conf_path) ->
        console.log "Meteor app at #{@root}"
        yamlfile = switch
            when fs.existsSync "#{@root}/setup.yaml"
                "#{@root}/setup.yaml"
            when fs.existsSync "#{@root}/.setup.yaml"
                "#{@root}/.setup.yaml"
            when fs.existsSync "#{@root}/.meteor/setup.yaml"
                "#{@root}/.meteor/setup.yaml"
            when extra_conf_path?
                for extra_conf_dir in extra_conf_path
                    console.log "also searching for config in #{extra_conf_dir}"
                    switch
                        when fs.existsSync "#{extra_conf_dir}/setup.yaml"
                            found = "#{extra_conf_dir}/setup.yaml"
                            break
                        when fs.existsSync "#{extra_conf_dir}/.setup.yaml"
                            found = "#{extra_conf_dir}/.setup.yaml"
                            break
                unless found?
                    throw new RunError 'no setup.yaml found'
                found
            else
                throw new RunError 'no setup.yaml found'
        @config = yaml.load yamlfile

require('./packages').patch MeteorApp
require('./development').patch MeteorApp
require('./deployment').patch MeteorApp
require('./load_balancer').patch MeteorApp

module.exports =
    MeteorApp: MeteorApp
    RunError: RunError
    main: (command = '', args = '') ->
        if args.length
            console.error 'No arguments supported at this point.'
            process.exit 1
        command = 'run' if command is ''
        try
            meteor_dir = switch
                when fs.existsSync '.meteor'
                    process.cwd()
                when fs.existsSync 'app/.meteor'
                    extra_conf_path = [process.cwd()]
                    "#{process.cwd()}/app"
                else
                    throw new RunError 'No Meteor app found'
            app = new MeteorApp meteor_dir, extra_conf_path
            if app[command]?.is_command
                app[command]()
            else
                console.error "No such command: #{command}"
                process.exit 1
        catch e
            if e instanceof RunError
                console.error e.message
                process.exit e.exit_code
            else
                throw e
