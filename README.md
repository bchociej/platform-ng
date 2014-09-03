platform-ng
===========

Rapid, sane configuration of ExpressJS. 0.2.x will probably be the last minor series to use express 3.

Platform-ng is retty robust at this point, and there are a handful of known production uses across at least 3 organizations.

That said, platform-ng has not been exhaustively tested, so use it at your own risk. Importantly, platform-ng is provided AS IS and WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTIBILITY OR FITNESS FOR A PARTICULAR PURPOSE.

Pull requests welcome, questions to bchociej on github or <platform-ng@chociej.io>.

App File (e.g. app.js)
----------------------

```javascript
require('platform-ng')('./config.json')
	.route('./routes/')
	.model('./models/')
	.source('./src/')
	.middleware('./middlewares/')
	.view('./src/view/')
	.log('./log/')
	.serve();
```

You can pass in a JS object instead of a JSON path for the config if you like.

See more information about **routes** and **models** below.

Configuration (e.g. config.json)
--------------------------------

Either in a json file, or in something ```require```able. Just needs to be a JS object.

You aren't truly required to pass in anything, really. The defaults are pretty sane. Here they are, with comments:

```javascript
{
	"app": {

		// must match /^[a-zA-Z0-9\-\.]$/
		"name": "unnammed-app",

		// 'development' or 'production'
		"env": "development",

		// you can disable using the "enabled" key below, or just set the whole
		// "session" value to something falsy
		"session": {
			"enabled": true,

			// cookie is the only supported type at the moment
			"type": "cookie",

			// you really should set this to some random, secure string
			"secret": "change me"
		},

		// disable with "enabled": false or just set "cookies" to something
		// falsy
		"cookies": {
			"enabled": true,

			// you really should set this to some random, secure string
			"secret": "change me"
		},

		// relative path to your favicon
		// default is express's builtin
		"favicon": "src/img/favicon.ico"
	},

	"server": {
		"port": 8001,

		// assume the node server is behind a reverse proxy?
		// this affects the value of req.ip, req.protocol, etc
		// it also affects how cookies are handled when set by proxy servers
		"behind_proxy": false,

		// parse document bodies passed to the server? JSON, multipart, etc
		// will get parsed and req.body will be transformed into something
		// more usable
		"body_parser": true,

		// allow POST requests to override the HTTP method by passing a field
		// named "_method"
		"method_override": false
	},

	"languages": {

		// enable the coffeescript compiler for *.coffee source files
		"coffeescript": true,

		// enable the stylus middleware for *.styl source files
		"stylus": {
			// when true, insert @included css files in-line rather than
			// outputting a css @import statement
			"include_css": true,

			// include the stylus nib library for cross-browser CSS3 mixins
			"nib": true
		}
	},

	"compile": {
		// when a preprocessor or compiler offers the option, should compiled
		// code be minified?
		"minify": true,

		// allow source files like .coffee, .styl, .jade, etc to be downloaded
		// from the sources directory; also causes some compilers to generate
		// source maps
		"expose_sources": true
	},

	// any option that can be set with express().set(key, value) can be included
	// in this hash
	"express": {
		"view engine": "jade"
	}
}
```

Data Models
-----------

When calling ```.model(modelsFn)``` on your platform-ng app, the ```modelsFn``` argument should be a function (or a ```require```able module exporting the same), which will receive these parameters:

```javascript
function modelsFn(config, logger, nodeEnvironment, callback)
```

The argument values will be as follows:

* ```config``` - the platform-ng configuration
* ```logger``` - a logger providing ```.info(msg)```, ```.warn(msg)```,
```.error(msg)```, and ```.log(level, msg)```, at the very least. Currently, the logger is winston.
* ```nodeEnvironment``` - either 'development' or 'production' depending on current configuration
* ```callback``` - the function to call after constructing your models, passing them back to platform-ng as an argument to the callback

These arguments are strictly for your own use in setting up models.

Note that if you use ```.model(...)``` you *must* call the callback, whether or not you pass anything
in, or else platform-ng will wait forever. If you don't call ```.model(...)```, platform-ng will
just skip the model initialization step.

Your models object, if any, will be passed to your routes for use in your application logic. A Mongoose example:

```javascript
// models.js
var schemas = require('./myMongooseSchemas.js');
var mongoose = require('mongoose');

module.exports = function(config, logger, nodeEnvironment, callback) {

	// Note that we've added a 'database' hash to our config for convenience
	mongoose.connect(config.database.conn_string);

	mongoose.connection.on('error', function(err) {
		logger.error('Database connection error: ' + err);
	});

	callback({
		BlogPost: mongoose.model('BlogPost', schemas.blogPostSchema),
		Comment: mongoose.model('Comment', schemas.commentSchema),
		Author: mongoose.model('Author', schemas.authorSchema)
	});
};
```

Middleware
----------

You can tell platform-ng to use custom middleware in your application. When calling
```.middleware(middlewareFn)```, middlewareFn should be (or be ```require```able as) a function which will
receive these parameters:

```javascript
function middlewareFn(models, config, logger, nodeEnvironment, callback)
```

The argument values will be as follows:

* ```models``` - Your models object, the result of calling your models function as described in the **Data Models** section
* ```config``` - the platform-ng configuration
* ```logger``` - a logger providing ```.info(msg)```, ```.warn(msg)```,
```.error(msg)```, and ```.log(level, msg)```, at the very least. Currently, the logger is winston.
* ```nodeEnvironment``` - either 'development' or 'production' depending on current configuration
* ```callback``` - The callback function which will receive your models. You should pass in either a single
middleware function or an array of middleware functions in the order you wish them to be applied. Middleware
functions should be compatible with the ```function``` definition in [Express 3.x's app.use doc](http://expressjs.com/3x/api.html#app.use).


Application Routes
------------------

When calling ```.route(routesFn)``` on your app, routesFn should be (or be ```require```able as) a function
which will receive these parameters:

```javascript
function routesFn(app, models, config, logger, nodeEnvironment, callback)
```

The argument values will be as follows:

* ```app``` - an Express-compatible API on which you should define your routes and middlewares, using ```.use()```, ```.param()```, any of the ```.VERB()``` functions, or ```.all()```. As of 0.1.0, you can use ```.namespace()``` as provided by the [express-namespace](https://github.com/visionmedia/express-namespace) module.
* ```models``` - Your models object, the result of calling your models function as described in the **Data Models** section
* ```config``` - the platform-ng configuration
* ```logger``` - a logger providing ```.info(msg)```, ```.warn(msg)```,
```.error(msg)```, and ```.log(level, msg)```, at the very least. Currently, the logger is winston.
* ```nodeEnvironment``` - either 'development' or 'production' depending on current configuration
* ```callback``` - The function to call after constructing your routes; you may pass back a routes object if that's something that you need, though typically a simple call to ```callback()``` is all that's needed here

Note that if you use ```.route(...)``` you *must* call the callback, whether or not you pass anything to it,
or else platform-ng will think an error has occurred in initializing the routes. Unlike models, platform-ng
will try to start up anyway if no routes callback is received, however, you will see an error message on exit.

If you don't use ```.route(...)```, platform-ng will skip the route initialization step.
