	module.exports =

## platform-ng config defaults

This literate Coffeescript file defines the default configuration options for platform-ng and explains
how can modify the configuration to suit your needs.

When you call `Platform#config()` with your configuration object, this configuration is deep-extended with
yours to produce the working configuration.

### General application configuration

What's the app called (`name`), and what environment is it running in (`env`)? For `env`, anything other
than the string `'production'` is automatically considered `'development'` for debuggability.

		app:
			name: 'unnamed-app'
			env: 'development'

For sessions, you can choose to entirely disable them by setting `enabled` to `false`. Otherwise, your
choices for `type` are currently `cookie` or `vanilla`.

The `cookie` type stores all session data in a garbled (not encrypted) client-side cookie, signed using
the `secret`.

The `vanilla` type stores the session in a server-side session store and only transmits a signed session
ID to the client.

`cookie` is default for now, but `vanilla` will replace it in the next major version. The `secure` option
determines whether the cookies are HTTPS-only or not.

			session:
				enabled: true
				type: 'cookie'
				secret: 'change-me'
				secure: false

The `cookies` section is for generic, non-session-related cookie usage. You can store anything in here that
you want the browser to remember. Again, `secret` signs and garbles the cookie contents, and `secure` means
HTTPS-only.

			cookies:
				enabled: true
				secret: 'change-me'
				secure: false

### HTTP server configuration

The `server` sections deals with how platform-ng handles the exchange, parsing, and encoding of HTTP
requests and responses.

		server:
			# Use automatic gzip compression for responses?
			compress: true

			# TCP port to listen on (overriden by PORT environment variable)
			port: 8001

			# Is the app behind a proxy? If so, replace request.ip with X-Forwarded-For, and trust
			# all cookies for HTTPS-only mode.
			behind_proxy: false

			# Enable/disable various body parsers, for performance and security reasons
			parsers:
				urlencoded: true
				json: true
				multipart: false # potential security problem; read http://goo.gl/N4Bci1

			# Allow requests to change HTTP verb using 'X-HTTP-Method-Override' header?
			method_override: false

### Language configuration

This section controls which protolanguages platform-ng will compile, as well as language-specific options
for some of the languages. (The NPM dependencies for these languages are listed in `package.json` as
`optionalDependencies` and can be skipped entirely by calling `npm install --no-optional`.)

		languages:
			coffeescript:
				enabled: true

			stylus:
				enabled: true
				include_css: true	# Whether to inline @include()'d CSS files
				nib: true			# Whether to automatically load the nib library

`compile` controls generic compilation options for all language compilers. The `minify` option will
cause the compiler to munge the output in order to produce the smallest possible code. The `expose_sources`
option will cause the server to serve the original files (e.g. .coffee, .styl, etc) if requested, AND it
will ask the compiler to generate source maps, if supported.

		compile:
			minify: true
			expose_sources: true 

platform-ng is powered by Express. You can directly configure Express settings here. The settings are
documented on [this page](http://expressjs.com/3x/api.html#app-settings).

		express:
			'view engine': 'jade'