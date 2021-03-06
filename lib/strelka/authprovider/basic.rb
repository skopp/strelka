# -*- ruby -*-
# vim: set nosta noet ts=4 sw=4:

require 'openssl'
require 'configurability'

require 'strelka' unless defined?( Strelka )
require 'strelka/app' unless defined?( Strelka::App )
require 'strelka/authprovider'
require 'strelka/mixins'

# HTTP Basic AuthProvider class -- a base class for RFC2617 Basic HTTP Authentication
# providers for {the Streka :auth plugin}[rdoc-ref:Strelka::App::Auth].
#
# == Configuration
#
# The configuration for this provider is read from the 'basicauth' section of the config, and
# may contain the following keys:
#
# [realm]::   the HTTP Basic realm. Defaults to the app's application ID
# [users]::   a Hash of username: SHA1+Base64'ed passwords
#
# An example:
#
#   --
#   auth:
#     provider: basic
#
#   basicauth:
#     realm: Acme Admin Console
#     users:
#       mgranger: "9d5lIumnMJXmVT/34QrMuyj+p0E="
#       jblack: "1pAnQNSVtpL1z88QwXV4sG8NMP8="
#       kmurgen: "MZj9+VhZ8C9+aJhmwp+kWBL76Vs="
#
# == Caveats
#
# This auth provider is intended as documentation and demonstration only; you should use a
# more cryptographically secure strategy for real-world applications.
#
class Strelka::AuthProvider::Basic < Strelka::AuthProvider
	extend Configurability,
	       Strelka::MethodUtilities
	include Strelka::Constants

	# Configurability API - set the section of the config
	config_key :basicauth

	# Configurability API -- configuration defaults
	CONFIG_DEFAULTS = {
		realm: nil,
		users: {},
	}


	##
	# The Hash of users and their SHA1+Base64'ed passwords
	singleton_attr_accessor :users

	##
	# The authentication realm
	singleton_attr_accessor :realm


	### Configurability API -- configure the auth provider instance.
	def self::configure( config=nil )
		if config && config[:realm]
			self.log.debug "Configuring Basic authprovider: %p" % [ config ]
			self.realm = config[:realm]
			self.users = config[:users]
		else
			self.log.warn "No 'basicauth' config section; using the (empty) defaults"
			self.realm = nil
			self.users = {}
		end
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################


	######
	public
	######

	# Check the authentication present in +request+ (if any) for validity, returning the
	# authenticating user's name if authentication succeeds.
	def authenticate( request )
		authheader = request.header.authorization or
			self.log_failure "No authorization header in the request."

		# Extract the credentials bit
		base64_userpass = authheader[ /^\s*Basic\s+(\S+)$/i, 1 ] or
			self.log_failure "Invalid Basic Authorization header (%p)" % [ authheader ]

		# Unpack the username and password
		credentials = base64_userpass.unpack( 'm' ).first
		self.log_failure "Malformed credentials %p" % [ credentials ] unless
			credentials.index(':')

		# Split the credentials, check for valid user
		username, password = credentials.split( ':', 2 )
		self.check_password( username, password )

		# Success!
		self.auth_succeeded( request, username )
		return username
	end


	#########
	protected
	#########

	### Return +true+ if the given +password+ is valid for the specified +username+. Always
	### returns false for non-existant users.
	def check_password( username, password )
		digest = self.class.users[ username ] or
			self.log_failure "No such user %p." % [ username ]

		# Fail if the password's hash doesn't match
		self.log_failure "Password mismatch." unless
			digest == Digest::SHA1.base64digest( password )

		return true
	end


	### Syntax sugar to allow returning 'false' while logging a reason for doing so.
	### Log a message at 'info' level and return false.
	def log_failure( reason )
		self.log.warn "Auth failure: %s" % [ reason ]
		header = "Basic realm=%s" % [ self.class.realm || self.app.conn.app_id ]
		finish_with( HTTP::AUTH_REQUIRED, "Requires authentication.", www_authenticate: header )
	end


end # class Strelka::AuthProvider::Basic
