express  = require 'express'
extend   = require 'extend'
thus     = require 'thus'
async    = require 'async'
path     = require 'path'
fs       = require 'fs'
rtprint  = require 'express-route-printer'

###
# The following modules might be included depending on configuration:
require 'stylus'
require 'nib'
require 'connect-coffee-script'
###

module.exports = (args...) ->
	new Platform args

maybe_require = (what) ->
	if typeof what is 'object'
		what
	else
		require what

hidden_files = []

class Platform
	constructor: (cfg) ->
		@config = extend true, {}, require('./defaults.json'), maybe_require(cfg)
		@logs = path.join(__dirname, './.logs/')
		@routes = () -> undefined
		@models = () -> undefined
		@

	routes: (rt) ->
		maybe_routes = maybe_require rts
		@routes = maybe_routes if typeof maybe_routes is 'function'
		@

	models: (mdl) ->
		maybe_models = maybe_require mdl
		@models = maybe_models if typeof maybe_models is 'function'
		@

	sources: (src) ->
		@sources = path.resolve src
		@

	views: (v) ->
		@views = path.resolve v
		@

	logs: (ld) ->
		@logs = path.resolve ld
		@

	serve: (srv) ->
		cfg = @config
		platform = @
		serve_dir = srv ? path.join(__dirname, './.serve/')

		unless /^[a-zA-Z0-9\-\.]+$/.test cfg.app.name
			throw new Error "Illegal app name: #{cfg.app.name}"

		port = process.env.PORT ? cfg.server.port
		node_env = process.env.NODE_ENV ? cfg.app.env

		async.each [platform.logs, s], fs.mkdir, ->
			if node_env isnt 'production'
				node_env = 'development'

			thus express(), ->
				@set 'env', node_env
				@set 'trust proxy', cfg.server.behind_proxy
				@set 'port', port
				@set 'views', path.join(__dirname, platform.views) if platform.views?
				@set k, v for k, v in cfg.express unless k in ['env', 'views', 'trust proxy']

				@use express.compress() if cfg.compress
				@use express.favicon() unless cfg.app.favicon?
				@use express.favicon(cfg.app.favicon) if cfg.app.favicon?

				winston.add winston.transports.File,
					filename: path.join(platform.logs, 'app.log')

				@configure 'development', ->
					@use express.logger('dev')
					@use express.errorHandler()

				@configure 'production', ->
					winston.remove winston.transports.Console

				@use express.logger
					format: 'short'
					stream: fs.createWriteStream path.join(platform.logs, 'express.log')

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

				if platform.sources?
					if cfg.languages?.coffeescript
						hidden_files.push 'coffee'
						coffeemw = require 'connect-coffee-script'

						@use coffeemw
							src: platform.sources
							dest: serve_dir
							sourceMap: cfg.compile?.expose_sources

					if cfg.languages?.stylus
						hidden_files.push 'styl'
						stylus = require 'stylus'

						@use stylus.middleware
							src: platform.sources
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

				@use express.static platform.sources
				@use express.static serve_dir

				# TODO: let models and routes define their stuff using callbacks
				# instead of synchronous calls
				compiled_models = platform.models cfg, winston, node_env
				compiled_routes = platform.routes @, compiled_models, cfg, winston, node_env

				rtprint @, winston

				@listen port

				winston.info "#{name} running"
				winston.info "ExpressJS listening on :#{port}"
