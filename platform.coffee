rtprint  = require 'express-route-printer'
through  = require 'through'
winston  = require 'winston'
express  = require 'express'
extend   = require 'extend'
moment   = require 'moment'
parser   = require 'body-parser'
thus     = require 'thus'
async    = require 'async'
path     = require 'path'
fs       = require 'fs'

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
-> EXPRESS 4.x!
-> The middlewares interface feels clunky...
###

codes =
	EXITING_CLEANLY: 0
	UNCAUGHT_EXCEPTION: 1
	INITIALIZATION_FAILED: 2
	ADDRESS_IN_USE: 3

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
		ctx.cfg = require './config-defaults.litcoffee'
		ctx.logs = path.join @wd, './logs/'
		ctx.routes = undefined
		ctx.models = undefined
		ctx.middlewares = undefined

	config: (c) ->
		ctx.cfg = extend true, {}, ctx.cfg, maybe_require(@wd, c)
		platform

	route: (rts) ->
		maybe_routes = maybe_require @wd, rts
		ctx.routes = maybe_routes if typeof maybe_routes is 'function'
		platform

	middleware: (mws) ->
		maybe_middleware = maybe_require @wd, mws
		ctx.middlewares = maybe_middleware if typeof maybe_middleware is 'function'
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

		console.log JSON.stringify(cfg, null, 4)

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

				switch @get 'env'
					when 'development'
						winston.info 'env = development'

						greystream = through (d) ->
							d = d.toString().stripColors
							d = d.split ' '

							d[0] = d[0].green
							d[1] = d[1].cyan

							d[2] = d[2].white.bold.redBG unless 200 <= parseInt(d[2]) < 300

							d = d.join ' '

							@queue d

						greystream.pipe process.stdout

						@use express.errorHandler()
						@use express.logger
							format: 'tiny'
							stream: greystream

					when 'production'
						winston.remove winston.transports.Console

				@use express.logger
					format: 'short'
					stream: fs.createWriteStream path.join(ctx.logs, 'express.log')

				compiled_models = compiled_routes = undefined
				models_ok = mws_ok = routes_ok = false

				if cfg.server.body_parser or cfg.server.parsers.body_parser
					if cfg.server.body_parser
						winston.warn 'deprecated cfg option server.body_parser (Connect 2 bodyParser)'
						winston.warn 'use server.parsers.* instead; json and urlencoded are on by default'
					else if cfg.server.parsers.body_parser
						winston.warn 'using deprecated Connect 2 bodyParser (cfg: server.parsers.body_parser)'

					@use express.bodyParser()

				@use parser.json({}) if cfg.server.parsers.json
				@use parser.urlencoded({extended: true}) if cfg.server.parsers.urlencoded
				@use express.multipart() if cfg.server.parsers.multipart

				app = @
				async.waterfall [
					do_models = (callback) ->
						models = ctx.models

						if typeof models isnt 'function'
							winston.warn 'no models detected, skipping'
							models = (cfg, logger, env, cb) ->
								cb()
						else
							winston.info 'setting up app-defined models'

						models cfg, winston, node_env, (mdl) ->
							compiled_models = mdl
							models_ok = true
							callback()
					,
					do_middlewares = (callback) ->
						mws = ctx.middlewares

						if typeof mws isnt 'function'
							mws = (models, cfg, logger, env, cb) ->
								cb()

						mws compiled_models, cfg, winston, node_env, (mw) ->
							if typeof mw is 'function'
								mw = [mw]

							if mw instanceof Array and mw.length > 0
								mw_count = 0

								for m in mw
									if typeof m is 'function'
										mw_count++
										app.use m
									else
										winston.warn "middleware at index #{mw.indexOf(m)} is not a function"

								winston.info "using #{mw_count} custom middleware#{if mw_count > 1 then 's' else ''}"

							mws_ok = true
							callback()
					,
					do_routes = (callback) ->
						routes = ctx.routes

						if typeof routes isnt 'function'
							winston.warn 'no routes detected, skipping'
							routes = (a, m, c, w, e, cb) ->
								cb()
						else
							winston.info 'setting up app-defined routes'

						routes app, compiled_models, cfg, winston, node_env, (r) ->
							compiled_routes = r
							routes_ok = true
							callback()
				], (err) ->
					if err?
						winston.error err
					else
						finish_setup()

				finish_setup = do (app = @) ->
					fn = ->
						@use express.methodOverride() if cfg.server.method_override

						@use express.cookieParser({
							secret: cfg.app.cookies?.secret,
							secure: cfg.app.cookies?.secure
						}) if cfg.app.cookies?.enabled

						@use @router

						if cfg.app.session?.enabled
							if cfg.app.session?.type is "cookie"
								@use express.cookieSession
									key: "#{cfg.app.name}.session"
									secret: cfg.app.session?.secret
									proxy: cfg.server.behind_proxy
							else if cfg.app.session?.type is "vanilla"
								@use express.session
									name: "#{cfg.app.name}.sid"
									secret: cfg.app.session?.secret
									cookie:
										secure: cfg.app.session?.secure
							else
								throw new Error "Unknown session type #{cfg.app.session?.type}"

						switch cfg.express['view engine']
							when 'jade' then hidden_files.push 'jade'

						if ctx.sources?
							if cfg.languages?.coffeescript?.enabled
								hidden_files.push 'coffee'
								coffeemw = require 'connect-coffee-script'

								@use coffeemw
									src: ctx.sources
									dest: serve_dir
									sourceMap: cfg.compile?.expose_sources

							if cfg.languages?.stylus?.enabled
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

						start_time = new Date
						@listen port
						rtprint @, winston

						winston.info "#{cfg.app.name} is running!"
						winston.info "platform-ng is listening via express on port #{port}"

					-> fn.call app


				said_bye = false
				exiter = (type) ->
					(error) ->
						unless said_bye
							end_time = new Date

							code = codes.EXITING_CLEANLY

							if type is 'uncaughtException'
								if error.code is 'EADDRINUSE'
									winston.error "port #{port} is already in use, so I can't bind to it. exiting."
									code = codes.ADDRESS_IN_USE
								else
									winston.error 'uncaught exception causing platform-ng to exit:'
									winston.error if typeof error is 'string' then error else JSON.stringify(error, null, 4)
									code = codes.UNCAUGHT_EXCEPTION

							else unless models_ok and routes_ok and mws_ok
								winston.error 'yikes! exiting early due to problems:'

								if not models_ok
									winston.error 'models initialization failed'
								else if not mws_ok
									winston.error 'middlewares initialization failed'
								else if not routes_ok
									winston.error 'routes initialization failed'

								code = codes.INITIALIZATION_FAILED

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

						unless type is 'exit'
							process.exit code

				process.on 'exit', exiter('exit')
				process.on 'SIGINT', exiter('SIGINT')
				process.on 'uncaughtException', exiter('uncaughtException')
