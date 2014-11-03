#!/usr/bin/perl
#
# DW::Controller::Misc
#
# This controller is for miscellaneous, tiny pages that don't have much in the
# way of actions.  Things that aren't hard to do and can be done in 10-20 lines.
# If the page you want to create is bigger, please consider creating its own
# file to house it.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      idonotlikepeas <peasbugs@gmail.com>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Misc;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/misc/feedping', \&feedping_handler, app => 1 );
DW::Routing->register_string( '/misc/whereami', \&whereami_handler, app => 1 );
DW::Routing->register_string( '/pubkey',        \&pubkey_handler,   app => 1 );
DW::Routing->register_string( '/guidelines',    \&community_guidelines, user => 1 );
DW::Routing->register_string( "/random/index", \&random_personal_handler, app => 1 );
DW::Routing->register_string( "/community/random/index", \&random_community_handler, app => 1 );

sub feedping_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 0 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $error_out = sub {
       my ( $code, $message ) = @_;
       $r->status( $code );
       $r->print( $message );
       return $r->OK;
    };

    my $out = sub {
        my ( $message ) = @_;
        $r->print( $message );
        return $r->OK;
    };

    return $out->( "This is a REST-like interface for pinging $LJ::SITENAMESHORT feed crawler to re-fetch a syndication URL.  Do a POST to this URL with a 'feed' parameter equal to the URL.  Possible HTTP responses are 400 (bad request), 404 (we're not indexing that feed), or 204 (we'll get to it soon).  (also permitted are multiple feed parameters, if you're not sure we're indexing your Atom vs RSS, etc.  At most 3 are currently accepted.)" )
            unless $r->did_post;


    my $post = $r->post_args;
    my $test_url = $post->{feed};
    return $error_out->( $r->HTTP_BAD_REQUEST, "No 'feed' parameter with URL." )
        unless $test_url;

    my @feeds = $post->get_all( "feed" );
    return $error_out->( $r->HTTP_BAD_REQUEST, "Too many 'feed' parameters." )
        if @feeds > 3;

    my $updated = 0;
    my $dbh = LJ::get_db_writer();
    foreach my $url ( @feeds ) {
        $updated = 1 if
            $dbh->do( "UPDATE syndicated SET checknext=NOW() WHERE synurl=?", undef, $url ) > 0;
    }

    return $out->( "Thanks! We'll get to it soon." )
        if $updated;

    return $error_out->( $r->NOT_FOUND, "Unknown feed(s)." );
}

# handles the /misc/whereami page
sub whereami_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $vars = { %$rv,
        cluster_name => $LJ::CLUSTER_NAME{$rv->{u}->clusterid} || LJ::Lang::ml( '/misc/whereami.tt.cluster.unknown' ),
    };

    return DW::Template->render_template( 'misc/whereami.tt', $vars );
}

# handle requests for a user's public key
sub pubkey_handler {
    return error_ml( '/misc/pubkey.tt.error.notconfigured' ) unless $LJ::USE_PGP;

    my ( $ok, $rv ) = controller( anonymous => 1, specify_user => 1 );
    return $rv unless $ok;

    $rv->{u}->preload_props( 'public_key' ) if $rv->{u};

    return DW::Template->render_template( 'misc/pubkey.tt', $rv );
}

sub community_guidelines {
    my ( $opts ) = @_;
    my $r = DW::Request->get;

    my $u = LJ::load_user( $opts->username );
    return error_ml( 'error.invaliduser' )  
        unless LJ::isu( $u );

    return error_ml( 'error.guidelines.notcomm' )
        unless $u->is_community;

    my $guidelines_entry = $u->get_posting_guidelines_entry;
    return error_ml( 'error.guidelines.none', { user => $u->ljuser_display, aopts => "href='" . $u->profile_url . "'" } )
        unless $guidelines_entry;

    return $r->redirect( $guidelines_entry->url );
}


sub random_community_handler {
    return _random_handler( journaltype => "C" );
}

sub random_personal_handler {
    return _random_handler( journaltype => "P" );
}

sub _random_handler {
    my ( %opts ) = @_;
    my $journaltype = $opts{journaltype};

    my $r = DW::Request->get;

    # repeat thrice just in case (may try a different cluster second time, or pull up a different set of users)
    my $u;
    foreach ( 1...3 ) {
        $u = LJ::User->load_random_user( $journaltype );
        return $r->redirect( $u->journal_base . "/" ) if $u;
    }

    # if we are unable to load a random journal / community, ask to try again
    my $ml_string = $journaltype eq "C" ? "random.retry.community" : "random.retry.personal";
    return error_ml( $ml_string, { aopts => "href='$LJ::SITEROOT" . $r->uri . "'" } );
}

1;
