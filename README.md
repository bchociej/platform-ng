platform-ng
===========

Rapid, sane configuration of ExpressJS.

App File (e.g. app.js)
----------------------

```javascript
require('platform-ng')('./config.json')
	.routes('./routes/')
	.models('./models/')
	.sources('./src/')
	.views('./src/view/')
	.logs('./log/')
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
		}
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

When calling ```.models(modelsFn)``` on your platform-ng app, the ```modelsFn``` argument should be a function (or a ```require```able module exporting the same), which will receive these parameters:

```javascript
function modelsFn(config, logger, nodeEnvironment)
```

The argument values will be as follows:

* ```config``` - the platform-ng configuration
* ```logger``` - a logger providing ```.info(msg)```, ```.warn(msg)```,
```.error(msg)```, and ```.log(level, msg)```, at the very least. Currently, the logger is winston.
* ```nodeEnvironment``` - either 'development' or 'production' depending on current configuration

These arguments are strictly for your own use in setting up models.

Your models function should (may) return a value that will be passed to your routes for use in your application logic. A Mongoose example:

```javascript
// models.js
var schemas = require('./myMongooseSchemas.js');
var mongoose = require('mongoose');

module.exports = function(config, logger, nodeEnvironment) {

	// Note that we've added a 'database' hash to our config for convenience
	mongoose.connect(config.database.conn_string);

	mongoose.connection.on('error', function(err) {
		logger.error('Database connection error: ' + err);
	});

	return {
		BlogPost: mongoose.model('BlogPost', schemas.blogPostSchema),
		Comment: mongoose.model('Comment', schemas.commentSchema),
		Author: mongoose.model('Author', schemas.authorSchema)
	};
};
```

Application Routes
------------------

When calling ```.routes(routesFn)``` on your app, routesFn should be (or be ```require```able as) a function
which will receive these parameters:

```javascript
function routesFn(app, models, config, logger, nodeEnvironment)
```

The argument values will be as follows:

* ```app``` - an Express-compatible API on which you should define your routes and middlewares, using ```.use()```, ```.param()```, any of the ```.VERB()``` functions, or ```.all()```
* ```models``` - Your models object, the result of calling your models function as described in the **Data Models** section
* ```config``` - the platform-ng configuration
* ```logger``` - a logger providing ```.info(msg)```, ```.warn(msg)```,
```.error(msg)```, and ```.log(level, msg)```, at the very least. Currently, the logger is winston.
* ```nodeEnvironment``` - either 'development' or 'production' depending on current configuration
