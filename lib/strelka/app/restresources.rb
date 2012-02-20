#!/usr/bin/env ruby

require 'sequel'

require 'strelka' unless defined?( Strelka )
require 'strelka/app' unless defined?( Strelka::App )


# RESTful resource utilities for Strelka::App.
#
# Stuff left to do:
#
# * Composite resources generated from associations
# * Honor If-unmodified-since and If-match headers
# * Caching support (ETag, If-modified-since)
# * Means of tailoring responses for requests for which the response
#   isn't clearly specified in the RFC (DELETE /resource)
# * Sequel plugin for adding links to serialized representations
module Strelka::App::RestResources
	extend Strelka::App::Plugin

	# Resource route option defaults
	DEFAULTS = {
		prefix:           '',
		name:             nil,
		readonly:         false,
		use_transactions: true,
	}.freeze


	### Inclusion callback -- overridden to also install dependencies.
	def self::included( mod )
		super

		# Load the plugins this one depends on if they aren't already
		mod.plugins :routing, :negotiation, :parameters

		# Add validations for the limit and offset parameters
		mod.param :limit, :integer
		mod.param :offset, :integer

		# Use the 'exclusive' router instead of the more-flexible
		# Mongrel2-style default one
		mod.router :exclusive
	end


	### Class methods to add to classes with REST resources.
	module ClassMethods
		include Sequel::Inflections

		# Routes to mounted resources
		@resource_routes = {}

		# Global options
		@global_options = DEFAULTS.dup

		# The list of REST routes assigned to Sequel::Model objects
		attr_reader :resource_routes

		# The global resource options hash
		attr_reader :global_options


		### Set the prefix for all following resource routes to +route+.
		def resource_prefix( route )
			self.global_options[ :prefix ] = route
		end


		### Expose the specified +rsrcobj+ (which should be an object that responds to #dataset
		### and returns a Sequel::Dataset)
		def resource( rsrcobj, options={} )
			Strelka.log.debug "Adding REST resource for %p" % [ rsrcobj ]
			options = self.global_options.merge( options )

			# Figure out what the resource name is, and make the route from it
			name = options[:name] || rsrcobj.implicit_table_name
			route = [ options[:prefix], name ].compact.join( '/' )

			# Add the resource for later lookup
			self.resource_routes[ rsrcobj ] = route

			# Set up parameters
			self.add_parameters( rsrcobj, options )

			# Make and install handler methods
			Strelka.log.debug "  adding readers"
			self.add_options_handler( route, rsrcobj, options )
			self.add_read_handler( route, rsrcobj, options )
			self.add_collection_read_handler( route, rsrcobj, options )

			# Add handler methods for the mutator parts of the API unless
			# the resource is read-only
			if options[:readonly]
				Strelka.log.debug "  skipping mutators (read-only set)"
			else
				self.add_collection_create_handler( route, rsrcobj, options )
				self.add_update_handler( route, rsrcobj, options )
				self.add_collection_update_handler( route, rsrcobj, options )
				self.add_delete_handler( route, rsrcobj, options )
				self.add_collection_deletion_handler( route, rsrcobj, options )
			end
		end


		### Add parameter declarations for parameters related to +rsrcobj+.
		def add_parameters( rsrcobj, options )
			Strelka.log.debug "Declaring validations for columns from %p" % [ rsrcobj ]
			self.untaint_all_constraints = true
			rsrcobj.db_schema.each do |col, config|
				Strelka.log.debug "  %s (%p)" % [ col, config[:type] ]
				param col, config[:type]
			end
		end


		### Add a handler method for discovery for the specified +rsrcobj+.
		### OPTIONS /resources
		def add_options_handler( route, rsrcobj, options )
			# :TODO: Documentation for HTML mode (possibly using http://swagger.wordnik.com/)
			Strelka.log.debug "Skipping OPTIONS %s handler for %p" % [ route, rsrcobj ]
		end


		### Add a handler method for reading a single instance of the specified +rsrcobj+, which should be a
		### Sequel::Model class or a ducktype-alike.
		### GET /resources/{id}
		def add_read_handler( route_prefix, rsrcobj, options )
			pkey = rsrcobj.primary_key
			route = "#{route_prefix}/:#{pkey}"

			Strelka.log.debug "Creating handler for reading a single %p: GET %s" % [ rsrcobj, route ]
			self.add_route( :GET, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join("\n") ) unless
					req.params.okay?

				id = req.params[ pkey ]
				resource = rsrcobj[ id ] or
					finish_with( HTTP::NOT_FOUND, "No such %s [%p]" % [rsrcobj.table_name, id] )

				res = req.response
				res.for( :json, :yaml ) { resource }

				return res
			end
		end


		### Add a handler method for reading a collection of the specified +rsrcobj+, which should be a
		### Sequel::Model class or a ducktype-alike.
		### GET /resources
		def add_collection_read_handler( route, rsrcobj, options )
			Strelka.log.debug "Creating handler for reading collections of %p: GET %s" % [ rsrcobj, route ]
			self.add_route( :GET, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join("\n") ) unless
					req.params.okay?

				limit, offset = req.params.values_at( :limit, :offset )
				res = req.response

				dataset = rsrcobj.dataset
				if limit
					self.log.debug "Limiting result set to %p records" % [ limit ]
					dataset = dataset.limit( limit, offset )
				end

				self.log.debug "Returning collection: %s" % [ dataset.sql ]
				res.for( :json, :yaml ) { dataset.all }

				return res
			end
		end


		### Add a handler method for creating a new instance of +rsrcobj+.
		### POST /resources
		def add_collection_create_handler( route, rsrcobj, options )
			Strelka.log.debug "Creating handler for creating %p resources: POST %s" % [ rsrcobj, route ]

			self.add_route( :POST, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join(", ") ) unless
					req.params.okay?

				resource = rsrcobj.new( req.params.valid )

				# Save it in a transaction, erroring if any of 'em fail validations
				begin
					resource.save
				rescue Sequel::ValidationFailed => err
					finish_with( HTTP::BAD_REQUEST, err.message )
				end

				# :TODO: Eventually, this should be factored out into the Sequel plugin
				resuri = [ req.base_uri, route, resource.pk ].join( '/' )

				res = req.response
				res.status = HTTP::CREATED
				res.headers.location = resuri
				res.headers.content_location = resuri

				res.for( :json, :yaml ) { resource }

				return res
			end
		end


		### Add a handler method for updating an instance of +rsrcobj+.
		### PUT /resources/{id}
		def add_update_handler( route_prefix, rsrcobj, options )
			pkey = rsrcobj.primary_key
			route = "#{route_prefix}/:#{pkey}"

			Strelka.log.debug "Creating handler for creating %p resources: POST %s" % [ rsrcobj, route ]
			self.add_route( :PUT, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join(", ") ) unless
					req.params.okay?

				id = req.params[ pkey ]
				resource = rsrcobj[ id ] or
					finish_with( HTTP::NOT_FOUND, "no such %s [%p]" % [ rsrcobj.name, id ] )

				newvals = req.params.valid
				newvals.delete( pkey.to_s )
				self.log.debug "Updating %p with new values: %p" % [ resource, newvals ]

				begin
					resource.update( newvals )
				rescue Sequel::Error => err
					finish_with( HTTP::BAD_REQUEST, err.message )
				end

				res = req.response
				res.status = HTTP::NO_CONTENT

				return res
			end
		end


		### Add a handler method for updating all instances of +rsrcobj+ collection.
		### PUT /resources
		def add_collection_update_handler( route, rsrcobj, options )
			pkey = rsrcobj.primary_key
			Strelka.log.debug "Creating handler for updating every %p resources: PUT %s" % [ rsrcobj, route ]

			self.add_route( :PUT, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join(", ") ) unless
					req.params.okay?

				newvals = req.params.valid
				newvals.delete( pkey.to_s )
				self.log.debug "Updating %p with new values: %p" % [ rsrcobj, newvals ]

				# Save it in a transaction, erroring if any of 'em fail validations
				begin
					rsrcobj.db.transaction do
						rsrcobj.update( newvals )
					end
				rescue Sequel::ValidationFailed => err
					finish_with( HTTP::BAD_REQUEST, err.message )
				end

				res = req.response
				res.status = HTTP::NO_CONTENT

				return res
			end
		end


		### Add a handler method for deleting an instance of +rsrcobj+ with +route_prefix+ as the base
		### URI path.
		### DELETE /resources/{id}
		def add_delete_handler( route_prefix, rsrcobj, options )
			pkey = rsrcobj.primary_key
			route = "#{route_prefix}/:#{pkey}"

			self.add_route( :DELETE, route, options ) do |req|
				finish_with( HTTP::BAD_REQUEST, req.params.error_messages.join(", ") ) unless
					req.params.okay?

				id = req.params[ pkey ]

				if resource = rsrcobj[ id ]
					self.log.debug "Deleting %p [%p]" % [ resource.class, id ]

					begin
						resource.destroy
					rescue Sequel::Error => err
						finish_with( HTTP::BAD_REQUEST, err.message )
					end
				end

				res = req.response
				res.status = HTTP::NO_CONTENT

				return res
			end
		end


		### Add a handler method for deleting all instances of +rsrcobj+ collection with +route+
		### as the base URI path.
		### DELETE /resources
		def add_collection_deletion_handler( route, rsrcobj, options )
			pkey = rsrcobj.primary_key
			Strelka.log.debug "Creating handler for deleting every %p resources: DELETE %s" %
				[ rsrcobj, route ]

			self.add_route( :DELETE, route, options ) do |req|
				self.log.debug "Deleting all %p objects" % [ rsrcobj ]

				# Save it in a transaction, erroring if any of 'em fail validations
				begin
					rsrcobj.db.transaction do
						rsrcobj.each {|obj| obj.destroy }
					end
				rescue Sequel::Error => err
					finish_with( HTTP::BAD_REQUEST, err.message )
				end

				res = req.response
				res.status = HTTP::NO_CONTENT

				return res
			end
		end

	end # module ClassMethods


end # module Strelka::App::RestResources
