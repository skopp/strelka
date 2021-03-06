# -*- ruby -*-
# vim: set nosta noet ts=4 sw=4:
# encoding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
}

require 'uri'
require 'rspec'
require 'spec/lib/helpers'
require 'strelka/cookie'
require 'strelka/cookieset'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Strelka::CookieSet do

	before( :each ) do
		@cookieset = Strelka::CookieSet.new
	end


	it "delegates some methods to its underlying Set" do
		cookie = Strelka::Cookie.new( 'pants', 'baggy' )

		@cookieset.should be_empty()
		@cookieset.length.should == 0
		@cookieset.member?( cookie ).should be_false()
	end

	it "is able to enummerate over each cookie in the set" do
		pants_cookie = Strelka::Cookie.new( 'pants', 'baggy' )
		shirt_cookie = Strelka::Cookie.new( 'shirt', 'pirate' )
		@cookieset << shirt_cookie << pants_cookie

		cookies = []
		@cookieset.each do |cookie|
			cookies << cookie
		end

		cookies.length.should == 2
		cookies.should include( pants_cookie )
		cookies.should include( shirt_cookie )
	end

	it "is able to add a cookie referenced symbolically" do
		pants_cookie = Strelka::Cookie.new( 'pants', 'denim' )
		@cookieset[:pants] = pants_cookie
		@cookieset['pants'].should == pants_cookie
	end


	it "autos-create a cookie for a non-cookie passed to the index setter" do
		lambda { @cookieset['bar'] = 'badgerbadgerbadgerbadger' }.should_not raise_error()

		@cookieset['bar'].should be_an_instance_of( Strelka::Cookie )
		@cookieset['bar'].value.should == 'badgerbadgerbadgerbadger'
	end

	it "raises an exception if the name of a cookie being set doesn't agree with the key it being set with" do
		pants_cookie = Strelka::Cookie.new( 'pants', 'corduroy' )
		lambda { @cookieset['shirt'] = pants_cookie }.should raise_error( ArgumentError )
	end

	it "implements Enumerable" do
		Enumerable.instance_methods( false ).each do |meth|
			@cookieset.should respond_to( meth )
		end
	end

	it "is able to set a cookie's value symbolically to something other than a String" do
		@cookieset[:wof] = Digest::MD5.hexdigest( Time.now.to_s )
	end

	it "is able to set a cookie with a Symbol key" do
		@cookieset[:wof] = Strelka::Cookie.new( :wof, "something" )
	end


	describe "created with an Array of cookies" do
		it "should flatten the array" do
			cookie_array = []
			cookie_array << Strelka::Cookie.new( 'foo', 'bar' )
			cookie_array << [Strelka::Cookie.new( 'shmoop', 'torgo!' )]

			cookieset = nil
			lambda {cookieset = Strelka::CookieSet.new(cookie_array)}.should_not raise_error()
			cookieset.length.should == 2
		end
	end


	describe "with a 'foo' cookie" do
		before(:each) do
			@cookie = Strelka::Cookie.new( 'foo', 'bar' )
			@cookieset = Strelka::CookieSet.new( @cookie )
		end

		it "contains only one cookie" do
			@cookieset.length.should == 1
		end

		it "is able to return the 'foo' Strelka::Cookie via its index operator" do
			@cookieset[ 'foo' ].should == @cookie
		end


		it "is able to return the 'foo' Strelka::Cookie via its symbolic name" do
			@cookieset[ :foo ].should == @cookie
		end

		it "knows if it includes a cookie named 'foo'" do
			@cookieset.should include( 'foo' )
		end

		it "knows if it includes a cookie referenced by :foo" do
			@cookieset.should include( :foo )
		end

		it "knows that it doesn't contain a cookie named 'lollypop'" do
			@cookieset.should_not include( 'lollypop' )
		end

		it "knows that it includes the 'foo' cookie object" do
			@cookieset.should include( @cookie )
		end


		it "adds a cookie to the set if it has a different name" do
			new_cookie = Strelka::Cookie.new( 'bar', 'foo' )
			@cookieset << new_cookie

			@cookieset.length.should == 2
			@cookieset.should include( new_cookie )
		end


		it "replaces any existing same-named cookie added via appending" do
			new_cookie = Strelka::Cookie.new( 'foo', 'giant scallops of doom' )
			@cookieset << new_cookie

			@cookieset.length.should == 1
			@cookieset.should include( new_cookie )
			@cookieset['foo'].should equal( new_cookie )
		end

		it "replaces any existing same-named cookie set via the index operator" do
			new_cookie = Strelka::Cookie.new( 'foo', 'giant scallops of doom' )
			@cookieset[:foo] = new_cookie

			@cookieset.length.should == 1
			@cookieset.should include( new_cookie )
			@cookieset['foo'].should equal( new_cookie )
		end

	end

end

# vim: set nosta noet ts=4 sw=4:
