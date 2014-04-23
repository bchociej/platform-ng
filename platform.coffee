rtprint = require 'express-route-printer'
winston = require 'winston'
express = require 'express'
extend  = require 'extend'
moment  = require 'moment'
thus    = require 'thus'
async   = require 'async'
path    = require 'path'
fs      = require 'fs'

###
The following modules might be included depending on configuration:
stylus
nib
connect-coffee-script
jade
###

###
TODOs

-> Instead of require()ing JSON, it should be read and JSON.parse()d
-> Add ability to 'watch' file changes, e.g. routes, models, app, config, etc
-> Add other preprocessor languages
-> The app that's passed in to routes should be an interface, not the real deal
-> Should the entire thing be configurable strictly in JSON?
	-> Or using chained function calls?
	-> Or either/or?
###

module.exports = (args...) ->
	new Platform args...

maybe_require = (wd, what) ->
	if typeof what is 'object'
		what
	else
		require path.resolve(wd, what)

class Platform
	platform = undefined
	ctx = {}

	constructor: (@wd) ->
		platform = @
		ctx.cfg = require './defaults.json'
		ctx.logs = path.join @wd, './logs/'
		ctx.routes = undefined
		ctx.models = undefined

	config: (c) ->
		ctx.cfg = extend true, {}, ctx.cfg, maybe_require(@wd, c)
		platform

	route: (rts) ->
		maybe_routes = maybe_require @wd, rts
		ctx.routes = maybe_routes if typeof maybe_routes is 'function'
		platform

	model: (mdl) ->
		maybe_models = maybe_require @wd, mdl
		ctx.models = maybe_models if typeof maybe_models is 'function'
		platform

	source: (src) ->
		ctx.sources = path.resolve @wd, src
		platform

	view: (v) ->
		ctx.views = path.resolve @wd, v
		platform

	log: (ld) ->
		ctx.logs = path.resolve @wd, ld
		platform

	serve: (srv) ->
		cfg = ctx.cfg
		serve_dir = srv ? path.join(@wd, './.serve/')
		wd = @wd
		hidden_files = []
		start_time = end_time = undefined

		unless /^[a-zA-Z0-9\-\.]+$/.test cfg.app.name
			throw new Error "Illegal app name: #{cfg.app.name}"

		port = process.env.PORT ? cfg.server.port
		node_env = process.env.NODE_ENV ? cfg.app.env

		async.each [ctx.logs, serve_dir], fs.mkdir, ->
			if node_env isnt 'production'
				node_env = 'development'

			thus express(), ->
				@set 'env', node_env
				@set 'trust proxy', cfg.server.behind_proxy
				@set 'port', port
				@set 'views', ctx.views if ctx.views?
				@set k, v for own k, v of cfg.express when k not in ['env', 'views', 'trust proxy', 'port']

				@locals.pretty = not cfg.compile?.minify

				@use express.compress() if cfg.server.compress
				@use express.favicon() unless cfg.app.favicon?
				@use express.favicon(path.join(wd, cfg.app.favicon)) if cfg.app.favicon?

				winston.add winston.transports.File,
					filename: path.join(ctx.logs, 'app.log')

				@configure 'development', ->
					@use express.logger('dev')
					@use express.errorHandler()

				@configure 'production', ->
					winston.remove winston.transports.Console

				@use express.logger
					format: 'short'
					stream: fs.createWriteStream path.join(ctx.logs, 'express.log')

				@use express.bodyParser() if cfg.server.body_parser
				@use express.methodOverride() if cfg.server.method_override
				@use express.cookieParser(cfg.app.cookies?.secret or null) if cfg.app.cookies?.enabled

				if cfg.app.session?.enabled
					if cfg.app.session?.type is "cookie"
						@use express.cookieSession
							key: "#{cfg.app.name}.session"
							secret: cfg.app.session?.secret
							proxy: cfg.server.behind_proxy
					else
						throw new Error "Unknown session type #{cfg.app.session?.type}"

				switch cfg.express['view engine']
					when 'jade' then hidden_files.push 'jade'

				if ctx.sources?
					if cfg.languages?.coffeescript
						hidden_files.push 'coffee'
						coffeemw = require 'connect-coffee-script'

						@use coffeemw
							src: ctx.sources
							dest: serve_dir
							sourceMap: cfg.compile?.expose_sources

					if cfg.languages?.stylus
						hidden_files.push 'styl'
						stylus = require 'stylus'

						@use stylus.middleware
							src: ctx.sources
							dest: serve_dir
							compile: (str, path, fn) ->
								s = stylus(str)
									.set('filename', path)
									.set('include css', cfg.languages?.stylus?.include_css)
									.set('compress', cfg.compile?.minify)

								if cfg.languages?.stylus?.nib
									s.use require('nib')()

				unless cfg.compile?.expose_sources
					app.get /.+/, (req, res, next) ->
						if req.path.split('.').pop() in hidden_files
							res.send 404
						else
							next()

				@use express.static ctx.sources
				@use express.static serve_dir

				compiled_models = compiled_routes = undefined
				models_ok = routes_ok = false

				do_models = (app, next) ->
					models = ctx.models

					if typeof models isnt 'function'
						winston.warn 'no models detected, skipping'
						models = (cfg, logger, env, cb) ->
							cb()
					else
						winston.info 'setting up models...'

					models cfg, winston, node_env, (m) -> next(app, m)

				do_routes = (app, models) ->
					models_ok = true
					compiled_models = models
					routes = ctx.routes

					if typeof routes isnt 'function'
						winston.warn 'no routes detected, skipping'
						routes = (a, m, c, w, e, cb) ->
							cb()
					else
						winston.info 'setting up routes...'

					routes app, compiled_models, cfg, winston, node_env, (r) ->
						compiled_routes = r
						routes_ok = true

					rtprint app, winston

					start_time = new Date
					app.listen port

					winston.info "#{cfg.app.name} running"
					winston.info "platform-ng listening via express on :#{port}"

				do_models(@, do_routes)

				said_bye = false
				exiter = ->
					unless said_bye
						end_time = new Date

						unless models_ok and routes_ok
							winston.error 'yikes! exited early due to problems with models and/or routes... check your models and routes!'
						else
							uptime = undefined

							if start_time? and end_time?
								hang = moment.duration(end_time - start_time)

								if hang.asSeconds() > 0
									uptime = ''
									uptime += (hang.years() + 'y ') if hang.years() > 0
									uptime += (hang.months() + 'M ') if hang.months() > 0
									uptime += (hang.days() + 'd ') if hang.days() > 0
									uptime += (hang.hours() + 'h ') if hang.hours() > 0
									uptime += (hang.minutes() + 'm ') if hang.minutes() > 0
									uptime += (hang.seconds() + 's ') if hang.seconds() > 0
									uptime = uptime.trim()

							winston.info 'platform-ng exiting cleanly. thanks for using!'

							if uptime?
								winston.info "uptime: #{uptime}"

					said_bye = true
					process.exit()

				process.on 'exit', exiter
				process.on 'SIGINT', exiter
