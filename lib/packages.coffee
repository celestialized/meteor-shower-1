fs = require 'fs'
DDPClient = require 'ddp'
shell = require 'shelljs'

module.exports = patch: (cls) ->
    cls::_connect_to_atmosphere = (done) ->
        if @_atmosphere_client?
            done()
        else
            ddpclient = new DDPClient
                host: 'atmosphere.meteor.com'
                port: 443
                use_ssl: true
            ddpclient.connect (err) =>
                if err?
                    console.error err
                    return done new RunError 'Failed to connect to Atmosphere'
                else
                    @_atmosphere_client = ddpclient
                    done()

    cls::_install_deps_from_atmosphere = (deps, done) ->
        dep = deps.shift()
        @_install_from_atmosphere dep.name, {version: dep.version}, (err) =>
            switch
                when err?
                    done err
                when deps.length
                    @_install_deps_from_atmosphere deps, done
                else
                    done()

    cls::_install_from_atmosphere = (name, options, done) ->
        @_connect_to_atmosphere =>
            ddpclient = @_atmosphere_client
            ddpclient.subscribe 'package', [name], =>
                # "package" is a reserved word
                for _id, pkg of ddpclient.collections.packages
                    if pkg.name is name
                        version = options.version or pkg.version
                        for pv in pkg.versions
                            if pv.version is version
                                if fs.existsSync "#{@root}/packages/#{name}"
                                    shell.pushd "#{@root}/packages/#{name}"
                                    shell.exec "git fetch #{pv.git}"
                                    shell.popd()
                                else
                                    shell.exec "git clone --recursive #{pv.git} #{@root}/packages/#{name}"
                                shell.pushd "#{@root}/packages/#{name}"
                                shell.exec "git checkout v#{version}"
                                shell.exec "git submodule update"
                                shell.popd()
                                deps = []
                                if pv.packages?
                                    # dependencies
                                    for dep_name, dep_options of pv.packages
                                        deps.push name: dep_name, version: dep_options.version
                                if deps.length
                                    console.log "installing #{name}'s dependencies: #{deps.join ', '}"
                                    return @_install_deps_from_atmosphere deps, done
                                else
                                    return done()
                        return done new RunError "Atmosphere package #{name} has no version #{version}"
                return done new RunError "No package named #{name} in Atmosphere"

    cls::install = (done, continuation) ->
        unless done?
            # called as a command
            done = ->
        return done() unless @config.packages?
        continuation ?= {}
        console.debug "in install; #{Object.keys(@config.packages).length - Object.keys(continuation).length} packgages left"
        for package_name, options of @config.packages
            continue if continuation[package_name]
            continuation[package_name] = true
            console.debug "installing #{package_name}"
            if fs.existsSync "#{@root}/packages/#{package_name}"
                switch options.from
                    when 'git'
                        unless shell.which 'git'
                            return done new RunError 'You don\'t seem to have git in your system. Please install it.'
                        console.log "updating #{package_name} from git: #{options.remote}"
                        shell.pushd "#{@root}/packages/#{package_name}"
                        shell.exec "git pull #{options.remote or 'origin'} #{options.ref or 'master'}"
                        shell.exec "git checkout #{options.ref or 'master'}"
                        shell.popd()
                    when 'atmosphere'
                        console.log "updating #{package_name} from atmosphere"
                        return @_install_from_atmosphere package_name, options, (err) =>
                            if err?
                                done err
                            else
                                console.debug 'done with atmosphere, continuing'
                                @install done, continuation
                    when 'bzr'
                        unless shell.which 'bzr'
                            return done new RunError 'You don\'t seem to have bzr in your system. Please install it.'
                        console.log "updating #{package_name} from bzr: #{options.branch}"
                        shell.pushd "#{@root}/packages/#{package_name}"
                        shell.exec "bzr pull #{options.branch}"
                        shell.popd()
                    when 'archive'
                        console.log "Sorry, updating from #{options.from} not yet implemented"
                    else
                        return done new RunError "Unknown installation method #{options.from}"
            else
                switch options.from
                    when 'git'
                        unless shell.which 'git'
                            return done new RunError 'You don\'t seem to have git in your system. Please install it.'
                        console.log "installing #{package_name} from git: #{options.remote}"
                        shell.exec "git clone --recursive #{options.remote} #{@root}/packages/#{package_name}"
                        if options.ref?
                            shell.pushd "#{@root}/packages/#{package_name}"
                            shell.exec "git checkout #{options.ref}"
                            shell.popd()
                    when 'bzr'
                        unless shell.which 'bzr'
                            return done new RunError 'You don\'t seem to have bzr in your system. Please install it.'
                        console.log "installing #{package_name} from bzr: #{options.branch}"
                        shell.exec "bzr branch #{options.branch} #{@root}/packages/#{package_name}"
                    when 'atmosphere'
                        console.log "installing #{package_name} from atmosphere"
                        return @_install_from_atmosphere package_name, options, (err) =>
                            if err?
                                done err
                            else
                                console.debug 'done with atmosphere, continuing'
                                @install done, continuation
                    when 'archive'
                        console.log "Sorry, installing from #{options.from} not yet implemented"
                    else
                        return done new RunError "Unknown installation method #{options.from}"
        done()
    cls::install.is_command = true
