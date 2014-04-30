#!/usr/bin/env perl

use strict;
use warnings;
use Mojolicious::Lite;
use Readonly;
use Time::HiRes qw(gettimeofday);
use Digest;
use 5.006;

our $VERSION = '1.0.0';

Readonly::Scalar my $endpoint => 'https://preact-sandbox.dk-hostmaster.dk/';

# Mojolicious has okay exception handling for now
## no critic (ErrorHandling::RequireUseOfExceptions)

# Our index page
get '/' => sub {
    my $self = shift;

    my $own_base_url
        = $self->req->url->{base}->scheme . '://'
        . $self->req->url->{base}->host . ':'
        . $self->req->url->{base}->port;

    # "Random" number with high resolution
    my $transactionid = gettimeofday();

    # We strip the separator for wider use
    $transactionid =~ s/\.//;

    # Defining dummy defaults:
    my $params = {
        'registrar.keyid' => '999888',    # mathes sandbox environment
        'registrar.url.on_accept' =>
            "$own_base_url/got_accepted",    # this application
        'registrar.url.on_reject' => "$own_base_url/got_rejected",    # ditto
        'registrar.url.on_error'  => "$own_base_url/got_error",       # ditto
        'registrar.url.on_edit'   => "$own_base_url/got_edit",        # ditto
        'registrar.transactionid' => $transactionid,    # generated id
        'registrar.reference'     => '',
        'registrar.language'      => 'en',
        'registrant.userid' => 'DKHM1-DK',    # mathes sandbox environment
        'domain.1.name'  => "test1$transactionid.dk",     # dummy domain
        'domain.2.name'  => "test2$transactionid.dk",     # ditto
        'domain.3.name'  => "test3$transactionid.dk",     # ditto
        'domain.4.name'  => "test4$transactionid.dk",     # ditto
        'domain.5.name'  => "test5$transactionid.dk",     # ditto
        'domain.6.name'  => "test6$transactionid.dk",     # ditto
        'domain.7.name'  => "test7$transactionid.dk",     # ditto
        'domain.8.name'  => "test8$transactionid.dk",     # ditto
        'domain.9.name'  => "test9$transactionid.dk",     # ditto
        'domain.10.name' => "test10$transactionid.dk",    # ditto
    };

    # We sort the domains by key
    my $sorted_domain_keys = _sort_domain_keys($params);

    $self->render(
        'index',
        params  => $params,
        domains => $sorted_domain_keys,
        version => $VERSION
    );
};

#preparing the request, requested from index (see above)
post '/prepare' => sub {
    my $self = shift;

    my $params = $self->req->params->to_hash;

# We sort the domains by key, order of the domains (keys) are important for the checksum
# calculation, see below
    my $sorted_domain_keys = _sort_domain_keys($params);

# We make all domainnames lower-case and create a list based on the sorted keys
    my @sorted_domains;
    foreach my $key ( @{$sorted_domain_keys} ) {
        if ( $params->{$key} ) {
            push @sorted_domains, lc $params->{$key};
        }
    }

    # We generate the checksum
    # and set the checksum on the parameter list just for convenience
    $params->{checksum} = _generate_checksum(
        $params->{'registrar.keyid'},
        $params->{'registrar.transactionid'},
        \@sorted_domains,
    );

    # We save the parameters if we are called back from the server
    # this should be a database or similar and is just here as a POC
    $self->session( $params->{transactionid} => $params );

    $self->render(
        'view',
        params      => $params,
        domains     => $sorted_domain_keys,
        form_action => $endpoint,
        version     => $VERSION,
    );
};

# call-back hook for accepted requests
get '/got_accepted' => sub {
    my $self = shift;
    $self->render(
        'got_accepted',
        params  => $self->req->params->to_hash,
        version => $VERSION
    );
};

# call-back hook for rejected requests
get '/got_rejected' => sub {
    my $self = shift;
    $self->render(
        'got_rejected',
        params  => $self->req->params->to_hash,
        version => $VERSION
    );
};

# call-back hook for errored requests, only validation and recoverable errors, critical errors are not
# for security reasons
get '/got_error' => sub {
    my $self = shift;
    $self->render(
        'got_error',
        params  => $self->req->params->to_hash,
        version => $VERSION
    );
};

# call-back hook for edit requests
get '/got_edit' => sub {
    my $self = shift;

    # selected parameters are echoed back from the server
    my $request_params = $self->req->params->to_hash;

    # we reinitialize the request we serialized for this particular situation
    # see prepare above again this should be a database or similar
    my $params = $self->session( $request_params->{transactionid} );

# selected parameters are echoed back from the server, so we retreive the original request
# to fill in the blanks, please note we let the echoed parameters have precedence, this
# should be validated for consistency
    foreach my $key ( keys %{$request_params} ) {
        $params->{$key} = $request_params->{$key};
    }

    # we sort the domain keys
    my $sorted_domain_keys = _sort_domain_keys($params);

    $self->render(
        'got_edit',
        params         => $params,
        domains        => $sorted_domain_keys,
        version        => $VERSION,
        request_params => $request_params,
    );
};

app->start;

# checksum generation
sub _generate_checksum {
    my ( $keyid, $transactionid, $domains ) = @_;

  # this record is the locally configuration of what is stored with the server
  # it should be in a configuration file or similar
    my $checksum_cfg = {
        keys => {
            999888 => {
                keytype       => 'SHA-256',
                shared_secret => 'dkhm-sandbox-test-secret',
                userid        => 'REG-999999',
            },
        },
    };

    my $key = $checksum_cfg->{keys}->{$keyid}
        or die "Unknown key id: $keyid";

    my @base = ( $key->{shared_secret}, $key->{userid}, $transactionid );

    my $joined = join ";", grep {defined} @base, @{$domains};

    my $checksum = Digest->new( $key->{keytype} )->add($joined)->hexdigest()
        or die "Unable to calculate checksum using key: $key";

    return lc $checksum;
}

# sorting domain keys, by the integer value in the middle of the string
sub _sort_domain_keys {
    my ($params) = @_;

    my @keys = ( grep {/^domain\.\d+.name$/} ( keys %{$params} ) );
    my @sorted_keys = sort {
        ( $a =~ /^domain\.(\d+).name$/ )[0]
            <=> ( $b =~ /^domain\.(\d+).name$/ )[0]
    } @keys;

    return \@sorted_keys;
}

=pod

=head1 NAME

DK Hostmaster pre-activation service demo client

=head1 VERSION

This documentation describes version 1.0.0

=head1 USAGE

    $ morbo  client.pl

Open your browser at:

    http://127.0.0.1:3000/

=head1 DEPENDENCIES

This client is implemented using Mojolicious::Lite in addition the following
Perl modules are used all available from CPAN.

=over

=item * Readonly

=item * Time::HiRes

=item * Digest

=back

In addition to the Perl modules, the client uses Twitter Bootstrap and hereby jQuery.
These are automatically downloaded via CDNs and are not distributed with the client
software.

=over

=item * http://getbootstrap.com/

=back

=head1 SEE ALSO

The main site for this client is the Github repository.

=over

=item * https://github.com/DK-Hostmaster/preact-demo-client-mojolicious

=back

For information on the service, please refer to the documentation page with
DK Hostmaster

=over

=item * https://www.dk-hostmaster.dk/english/technical-administration/tech-notes/pre-activation/

=back

=head1 COPYRIGHT

This software is under copyright by DK Hostmaster A/S 2014

=head1 LICENSE

This software is licensed under the MIT software license

Please refer to the LICENSE file accompanying this file.

=cut

__DATA__

@@ got_error.html.ep
% layout 'default', title 'Error: on_error callback';
<div class="alert alert-danger">
<strong>Request did not validate and returned with an error</strong>
</div>

%= include 'param_list', params => $params;

<button type="button" onclick="window.history.go(-2);" class="btn btn-default">Edit request</button>

@@ got_accepted.html.ep
% layout 'default', title 'Accepted: on_accept callback';
<div class="alert alert-success">
<strong>Looking good, user accepted request and we got token: <%= $params->{token} %></strong>
</div>

<form class="form-horizontal" role="form" action="/" method="GET" accept-charset="UTF-8">

%= include 'param_list', params => $params;

<button class="btn btn-default" type="submit">Start over</button>

</form>

@@ got_rejected.html.ep
% layout 'default', title 'Rejected: on_reject callback';
<div class="alert alert-warning">
<strong>Too bad, user rejected request</strong>
</div>

<form class="form-horizontal" role="form" action="/" method="GET" accept-charset="UTF-8">

%= include 'param_list', params => $params;

<button class="btn btn-default" type="submit">Start over</button>

</form>

@@ got_edit.html.ep
% layout 'default', title 'Edit: on_edit callback';
<div class="alert alert-info">
<strong>User requests additional edit</strong>
</div>

<% my @keys = sort (keys %{$request_params}); %>

<h3>Received parameters:</h3>
<p>
<table class="table table-striped">
  <thead>
    <tr><th>Parameter</th><th>Value</th></tr>
  </thead>
  <tbody>
  % foreach my $p (@keys) {
    <tr><td>[<code><%= $p %></code>]</td><td><%= $params->{$p} %></td></tr>
  % }
  </tbody>
</table>
</p>

%= include 'edit';

@@ param_list.html.ep

<% foreach my $key (keys %{$params}) {
  if (not $params->{$key}) {
    delete $params->{$key};
  }
} %>

<% my @keys = sort (keys %{$params}); %>

<p>
<table class="table table-striped">
  <thead>
    <tr><th>Parameter</th><th>Value</th></tr>
  </thead>
  <tbody>
  % foreach my $p (@keys) {
    <tr><td>[<code><%= $p %></code>]</td><td><%= $params->{$p} %></td><input name="<%= $p %>" type="hidden" value="<%= $params->{$p} %>"></tr>
  % }
  </tbody>
</table>
</p>

@@ index.html.ep
% layout 'default', title 'Edit data';

%= include 'edit';

@@ view.html.ep
% layout 'default', title 'View data';

<form class="form-horizontal" role="form" action="<%= $form_action %>" method="POST" accept-charset="UTF-8">

%= include 'param_list', params => $params;


  <div class="panel panel-info">
  <div class="panel-heading">
  Checksum calculation
  </div>
  <div class="panel-body" style="word-wrap:break-word;">
  <p><h5>Elements:</h5></p>
  <p><kbd>shared secret</kbd>;<kbd>registrar userid</kbd>;<code>registrar.transactionsid</code>;<code>domain.N.name</code>; .. <code>domain.N+1.name</code></p>
  <p><h5>Example elements (from above request):</h5></p>
  <p>dkhm-sandbox-test-secret;REG-999999;<%= $params->{'registrar.transactionid'};foreach my $domain (@{$domains}) { %>;<%= $params->{$domain} %><% } %>
  </p>
  <p><h5>Hexidecimal digest of the below string, using SHA-256:</h5></p>
  <p><%= $params->{'checksum'} %></p>
  </div>
  </div>

<button type="submit" class="btn btn-primary">Send request to <%= $form_action %> <span class="glyphicon glyphicon-send"></span></button>
<button type="button" onclick="window.history.back();" class="btn btn-default">Edit request</button>

</form>

@@ edit.html.ep
<form class="form-horizontal" role="form" action="/prepare" method="POST" accept-charset="UTF-8">

    <legend>Registrar</legend>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.keyid">Key-id:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" id="registrar.keyid" placeholder="registrar.keyid" name="registrar.keyid" type="text" value="<%= $params->{'registrar.keyid'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">Id identifying registrars key stored on the client and registry sides [<code>registrar.keyid</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.url.on_error">Error handler:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.url.on_error" name="registrar.url.on_error" value="<%= $params->{'registrar.url.on_error'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">URL for receiving call-backs on data error [<code>registrar.url.on_error</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.url.on_edit">Edit handler:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.url.on_edit" name="registrar.url.on_edit" value="<%= $params->{'registrar.url.on_edit'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">URL for receiving call-backs on edit requested by user [<code>registrar.url.on_edit</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.url.on_reject">Rejection handler:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.url.on_reject" name="registrar.url.on_reject" value="<%= $params->{'registrar.url.on_reject'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">URL for receiving call-backs on reject by user [<code>registrar.url.on_reject</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.url.on_accept">Acceptance handler:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.url.on_accept" name="registrar.url.on_accept" value="<%= $params->{'registrar.url.on_accept'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">URL for receiving call-backs on accept by user [<code>registrar.url.on_accept</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.transactionid">Transaction-id:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.transactionid" name="registrar.transactionid" value="<%= $params->{'registrar.transactionid'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">Registrars transaction id [<code>registrar.transactionid</code>]</p></div>
    </div>
    </div>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.reference">Reference:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" type="text" placeholder="registrar.reference" name="registrar.reference" value="<%= $params->{'registrar.reference'} %>">
        </div>
      </div>
      <div class="col-sm-6"><p class="help-block">Registrars reference [<code>registrar.reference</code>]</p></div>
    </div>
    </div>

    <% my $language = $params->{'registrar.language'}; %>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrar.language">Presentation Language:</label>

      <div class="controls">
      <div class="col-sm-4">
      <input class="radio-inline input-sm" type="radio" name="registrar.language" value="da"<%= 'checked="checked"' if ($language eq 'da') %>> Dansk</input>
      <input class="radio-inline input-sm" type="radio" name="registrar.language" value="en"<%= 'checked="checked"' if ($language eq 'en') %>> English</input>
      <input class="radio-inline input-sm" type="radio" name="registrar.language" value=""<%= 'checked="checked"' if ($language eq '') %>> <i>(None)</i></input>
      </div>
      </div>
      <div class="col-sm-6"><p class="help-block">The <b>pre-activation service</b> will be presented in this language to the user. Id must be in ISO 639-1, meaning <code>da</code> or <code>en</code> (<a href="https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes">reference</a>) [<code>registrar.language</code>]</p>
      </div>
    </div>
    </div>

    <legend>Registrant</legend>
    <p class="help-block">Existing user</p>

    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrant.userid">User-id:</label>
      <div class="controls">
        <div class="col-sm-4">
        <input class="form-control" placeholder="registrant.userid" name="registrant.userid" type="text" value="<%= $params->{'registrant.userid'} %>">
        </div>
      </div>
      <div class="col-sm-4"><p class="help-block">User-id of existing user [<code>registrant.userid</code>]</p></div>
    </div>
    </div>

    <hr>
    <p class="help-block">Or creation of new user</p>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.name">Name:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.name" name="registrant.name" value="<%= $params->{'registrant.name'} %>" />
    </div>
    </div>
    <div class="col-sm-4"><p class="help-block">Name of registrant [<code>registrant.name</code>]</p></div>
    </div>

    <% my $type = $params->{'registrant.type'}; %>
    <div class="form-group">
    <div class="control-group">
      <label class="control-label col-sm-2" for="registrant.type">User type:</label>

      <div class="controls">
      <div class="col-sm-6">
      <input class="radio-inline input-sm" type="radio" name="registrant.type" value="I"<%= 'checked="checked"' if ($type eq 'I') %>> Individual</input>
      <input class="radio-inline input-sm" type="radio" name="registrant.type" value="C"<%= 'checked="checked"' if ($type eq 'C') %>> Company</input>
      <input class="radio-inline input-sm" type="radio" name="registrant.type" value="P"<%= 'checked="checked"' if ($type eq 'P') %>> Public Organisation</input>
      <input class="radio-inline input-sm" type="radio" name="registrant.type" value="A"<%= 'checked="checked"' if ($type eq 'A') %>> Association</input>
      <input class="radio-inline input-sm" type="radio" name="registrant.type" value=""<%= 'checked="checked"' if ($type eq '') %>> <i>(None)</i></input>
      <p class="help-block">Type of new user [<code>registrant.type</code>]</p>
      </div>
      </div>
    </div>

    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.vatnumber">Vatnumber:</label>
    <div class="col-sm-4">
    <input class="form-control" placeholder="registrant.vatnumber" type="text" name="registrant.vatnumber" value="<%= $params->{'registrant.vatnumber'} %>"/>
    </div>
    </div>
    <div class="col-sm-4"><p class="help-block">VAT number [<code>registrant.vatnumber</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.street1">Street 1:</label>
    <div class="col-sm-4">
    <input class="form-control" placeholder="registrant.address.street1" type="text" name="registrant.address.street1" value="<%= $params->{'registrant.address.street1'} %>" />
    </div>
    </div>
    <div class="col-sm-4"><p class="help-block">Address part 1 [<code>registrant.address.street1</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.street2">Street 2:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.address.street2" name="registrant.address.street2" value="<%= $params->{'registrant.address.street2'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Address part 2 [<code>registrant.address.street2</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.street3">Street 3:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.address.street3" name="registrant.address.street3" value="<%= $params->{'registrant.address.street3'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Address part 3 [<code>registrant.address.street3</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.zipcode">Zipcode:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.address.zipcode" name="registrant.address.zipcode" value="<%= $params->{'registrant.address.zipcode'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Zipcode [<code>registrant.address.zipcode</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.city">City:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.address.city" name="registrant.address.city" value="<%= $params->{'registrant.address.city'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">City [<code>registrant.address.city</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.address.countryregionid">Country:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.address.countryregionid" name="registrant.address.countryregionid" value="<%= $params->{'registrant.address.countryregionid'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Id for country using ISO 3166-1 alpha-2, (<a href="https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2">reference</a>) [<code>registrant.address.countryreqionid</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.email">Email:</label>
    <div class="col-sm-4">
    <input class="form-control" type="email" id="registrant.email" placeholder="registrant.email" name="registrant.email" placeholder="registrant.email" value="<%= $params->{'registrant.email'} %>" />
    </div>
    </div>
    <div class="col-sm-4"><p class="help-block">Email address [<code>registrant.email</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.phone">Phone:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.phone" name="registrant.phone" value="<%= $params->{'registrant.phone'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Phonenumber, specify international dialing code where applicable (<a href="https://en.wikipedia.org/wiki/List_of_country_calling_codes">reference</a>) [<code>registrant.phone</code>]</p></div>
    </div>

    <div class="form-group">
    <div class="control-group">
    <label class="control-label col-sm-2" for="registrant.telefax">Fax:</label>
    <div class="col-sm-4">
    <input class="form-control" type="text" placeholder="registrant.telefax" name="registrant.telefax" value="<%= $params->{'registrant.telefax'} %>" />
    </div>
    </div>
    <div class="col-sm-6"><p class="help-block">Faxnumber, specify international dialing code where applicable (<a href="https://en.wikipedia.org/wiki/List_of_country_calling_codes">reference</a>) [<code>registrant.fax</code>]</p></div>
    </div>

    <legend>Domains:</legend>
    <p class="help-block">Max 10 domainnames per request</p>

    <% my $i = 1; %>
    <% for my $domain (@{$domains}) { %>
        <div class="form-group">
        <div class="control-group">
        <label class="control-label col-sm-2" for="<%= $domain %>">Domain <%= $i %>:</label>
          <div class="col-sm-4">
            <input class="form-control" input type="text" name="<%= $domain %>" value="<%= $params->{$domain} %>" />
          </div>
        </div>
        <div class="col-sm-6"><p class="help-block">[<code><%= $domain %></code>]</p></div>
        </div>
    <% $i++; %>
    <% } %>

    <% for ((scalar @{$domains}+1) .. 10) { %>
        <% my $number_of_domains; %>
        <div class="form-group">
        <div class="control-group">
        <label class="control-label col-sm-2" for="domain.<%= $_ %>.name">Domain <%= $_ %>:</label>
          <div class="col-sm-4">
            <input class="form-control" input type="text" placeholder="domain.<%= $_ %>.name" name="domain.<%= $_ %>.name" />
          </div>
        </div>
        <div class="col-sm-6"><p class="help-block">[<code>domain.<%= $_ %>.name</code>]</p></div>
        </div>
    <% } %>


    <button type="submit" class="btn btn-primary">Prepare request</button>
    <button class="btn btn-default" type="reset">Reset to defaults</button>
    <button onclick="clear_form_elements(this.form)" class="btn btn-danger" type="button">Clear ALL</button>

</form>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta .epp-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= title %></title>

    <!-- Bootstrap -->
    <!-- Latest compiled and minified CSS -->
    <link rel="stylesheet" href="https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css">
    <!-- Optional theme -->
    <link rel="stylesheet" href="https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap-theme.min.css">

    <!-- http://www.electrictoolbox.com/jquery-clear-form/ -->
    <script language="javascript">
    function clear_form_elements(element) {
      $(element).find(':input').each(function() {

        switch(this.type) {
            case 'password':
            case 'select-multiple':
            case 'select-one':
            case 'text':
            case 'textarea':
                $(this).val('');
                break;
            case 'checkbox':
            case 'radio':
                this.checked = false;
          }
      });
    }
    </script>

    <!-- HTML5 Shim and Respond.js IE8 support of HTML5 elements and media queries -->
    <!-- WARNING: Respond.js doesn't work if you view the page via file:// -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/libs/html5shiv/3.7.0/html5shiv.js"></script>
      <script src="https://oss.maxcdn.com/libs/respond.js/1.4.2/respond.min.js"></script>
    <![endif]-->
  </head>
  <body role="document">
    <div class="container">
    <a href="https://github.com/DK-Hostmaster/preact-demo-client-mojolicious"><img style="position: absolute; top: 0; right: 0; border: 0;" src="https://camo.githubusercontent.com/365986a132ccd6a44c23a9169022c0b5c890c387/68747470733a2f2f73332e616d617a6f6e6177732e636f6d2f6769746875622f726962626f6e732f666f726b6d655f72696768745f7265645f6161303030302e706e67" alt="Fork me on GitHub" data-canonical-src="https://s3.amazonaws.com/github/ribbons/forkme_right_red_aa0000.png"></a>
    <h1>DK Hostmaster pre-activation service demo client - Version <%= $version %></h1>
    <p class="lead"><%= $title %></p>

    <p><%= content %></p>

    </div>

    <!-- jQuery (necessary for Bootstrap's JavaScript plugins) -->
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js"></script>
    <!-- Latest compiled and minified JavaScript -->
    <script src="https://netdna.bootstrapcdn.com/bootstrap/3.1.1/js/bootstrap.min.js"></script>

  </body>
</html>
