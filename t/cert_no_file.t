#!perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl t/nonblock.t'

# Tests the use if SSL_cert instead of SSL_cert_file
# because Net::SSLeay does not implement the necessary functions
# to create a X509 from file/string (PEM_read_bio_X509) I just
# create a server with SSL_cert_file and get the X509 from it using
# Net::SSLeay::get_certificate.
# Test should also test if SSL_cert is an array of X509*
# and if SSL_key is an EVP_PKEY* but with the current function in
# Net::SSLeay I don't see a way to test it

use strict;
use warnings;
use Net::SSLeay;
use Socket;
use IO::Socket::SSL;

use Test::More tests => 9;
Test::More->builder->use_numbers(0);
Test::More->builder->no_ending(1);

my $ID = 'server';
my %server_args = (
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Listen => 2,
    SSL_server => 1,
    SSL_verify_mode => 0x00,
    SSL_ca_file => "certs/test-ca.pem",
    SSL_key_file => "certs/client-key.pem",
);

my ($x509,@server);
foreach my $test ( 1,2,3 ) {
    my %args = %server_args;
    my $spec;
    if ( $test == 1 ) {
	# 1st test:  create server with SSL_cert_file
	$args{SSL_cert_file} = "certs/client-cert.pem";
	$spec = 'Using SSL_cert_file';
    } elsif ( $test == 2 ) {
	# 2nd test:  use x509 from previous server
	# with SSL_cert instead of SSL_cert_file
	$args{SSL_cert} = $x509;
	$spec = 'Using SSL_cert';
    } elsif ( $test == 3 ) {
	# 3rd test: empty SSL_cert, so that default
	# SSL_cert_file gets not used
	# server creation should fail
	$spec = 'Empty SSL_cert';
	$args{SSL_cert} = undef;
    }

    # create server
    my $server = IO::Socket::SSL->new( %args ) || do {
       fail( "$spec: $!" );
	next;
    };

    my $saddr = $server->sockhost.':'.$server->sockport;
    ok(1, "Server Initialization $spec");
    push @server,$server;

    # then connect to it from a child
    defined( my $pid = fork() ) || die $!;
    if ( $pid == 0 ) {
	close($server);
	$ID = 'client';

	my $to_server = IO::Socket::SSL->new(
	    PeerAddr => $saddr,
	    SSL_verify_mode => 0x00,
	);
	if ( $test == 3 ) {
	    ok( !$to_server, "$spec: connect succeeded" );
        exit;
	} elsif ( ! $to_server ) {
	    plan skip_all => "connect failed: $!";
	};
	ok( 1, "client connected $spec" );
	<$to_server>; # wait for close from parent
	exit;
    }

    my $to_client = $server->accept;
    if ( $test == 3 ) {
	ok( !$to_client, "$spec: accept succeeded" );
    } elsif ( ! $to_client ) {
	kill(9,$pid);
	plan skip_all => "$spec: accept failed: $!";
    } else {
	ok(1, "Server accepted $spec" );
	# save the X509 certificate from the server
	$x509 ||= Net::SSLeay::get_certificate($to_client->_get_ssl_object);
    }

    close($to_client) if $to_client;
    wait;
}

