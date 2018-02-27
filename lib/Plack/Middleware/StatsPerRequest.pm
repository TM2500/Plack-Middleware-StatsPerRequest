package Plack::Middleware::StatsPerRequest;

# ABSTRACT: Measure HTTP stats on each request

our $VERSION = '0.900';

use strict;
use warnings;
use 5.010;
use Time::HiRes qw();

use parent 'Plack::Middleware';
use Plack::Util::Accessor qw( app_name metric_name path_cleanups add_headers long_request );
use Plack::Request;
use Log::Any qw($log);
use Measure::Everything qw($stats);
use HTTP::Headers::Fast;

sub prepare_app {
    my $self = shift;

    $self->app_name('unknown') unless $self->app_name;
    $self->metric_name('http_request') unless $self->metric_name;
    $self->path_cleanups([\&replace_idish]) unless $self->path_cleanups;
    $self->long_request(5) unless defined $self->long_request;
}

sub call {
    my $self = shift;
    my $env  = shift;

    my $t0 = [Time::HiRes::gettimeofday];

    my $res = $self->app->($env);

    return Plack::Util::response_cb(
        $res,
        sub {
            my $res = shift;
            my $req;

            my $elapsed = Time::HiRes::tv_interval($t0);
            $elapsed = sprintf( '%5f', $elapsed ) if $elapsed < .0001;

            my $path = $env->{PATH_INFO};
            foreach my $callback (@{$self->path_cleanups}) {
                $path = $callback->($path);
            }

            my %tags = (
                status => $res->[0],
                method => $env->{REQUEST_METHOD},
                app    => $self->app_name,
                path   => $path,
            );
            if (my $headers_to_add = $self->add_headers) {
                foreach my $header (@$headers_to_add) {
                    $req = Plack::Request->new( $env );
                    $tags{'header_'.lc($header)} = $req->header($header) // 'not_set';
                }
            }

            eval {
                $stats->write(
                    $self->metric_name,
                    { request_time => $elapsed, hit => 1 },
                    \%tags
                );
                if ( $self->long_request &&  $elapsed > $self->long_request ) {
                    $req ||= Plack::Request->new($env);
                    $log->warnf(
                        "Long request, took %f: %s %s",
                        $elapsed,
                        $req->method,
                        $req->request_uri
                    );
                }
            };
            if ($@) {
                $log->errorf( "Could not write stats: %s", $@ );
            }
        }
    );
}

=method replace_idish

  my $clean = Plack::Middleware::StatsPerRequest::replace_idish( $dirty );

Takes a URI path and replaces things that look like ids with fixed
strings, so you can calc proper stats on the generic paths.

This is the default L<path_cleanups> action, so unless you specify
your own, or explicitly set L<path_cleanups> to an empty array, the
following transformations will be done on the path:

=over

=item * All path fragments looking like a SHA1 checksum are replaced by
C<:sha1>.

=item * All path fragments looking like a UUID are replaced by C<:uuid>.

=item * Any part of the path consisting of 6 or more digits is
replaced by C<:int>.

=item * A llpath fragments consisting solely of digits are also replaced
by C<:int>.

=item * All path fragments looking like hex are replaced by C<:hex>.

=item * All path fragments longer than 55 characters are replaced by
C<:long>.

=item * A chain of path fragments looking like hex-code is replaced by
C<:hexpath>.

=item * All path fragments looking like an email message id (as generated
by one of our tools) are replaced by C<:msgid>.

=item * All path fragments looking like C<300x200> are replaced by
C<:imgdim>. (Of course this happens for all formats, not just 300 and 200).

=back

For details, please inspect the source code and
F<t/20_replace_idish.t>.

These transformations proved useful in the two years we used
C<Plack::Middleware::StatsPerRequest> in house. If you have any
additions or change requests, just tell us!

=cut

sub replace_idish {
    my $path = shift;
    $path = lc($path . '/');

    $path =~ s{/[a-f0-9\-.]+\@[a-z0-9\-.]+/}{/:msgid/}g;
    $path =~ s{/[a-f0-9]+\/[a-f0-9\/]+/}{/:hexpath/}g;

    $path =~ s([a-f0-9]{40})(:sha1)g;
    $path =~ s([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})(:uuid)g;
    $path =~ s(\d{6,})(:int)g;
    $path =~ s{\d+x\d+}{:imgdim}g;

    $path =~ s{/\d+/}{/:int/}g;
    $path =~ s(/[^/]{55,}/)(/:long/)g;
    $path =~ s(/[a-f0-9\-]{8,}/)(/:hex/)g;

    return substr($path, 0, -1);
}

"42nd birthday release";

__END__

=head1 SYNOPSIS

  use Plack::Builder;
  use Measure::Everything::Adapter;
  Measure::Everything::Adapter->set('InfluxDB::File', {
      file => '/tmp/yourapp.stats',
  });

  builder {
      enable "Plack::Middleware::StatsPerRequest",
          app_name => 'YourApp',
      ;
      $app;
  };

  # curl http://localhost:3000/some/path
  # cat /tmp/yourapp.stats
    http_request,app=YourApp,method=GET,path=/some/path,status=400 hit=1i,request_time=0.02476 1519658691411352000

=head1 DESCRIPTION

C<Plack::Middleware::StatsPerRequest> lets you collect stats about all your
HTTP requests via L<Measure::Everything>.
C<Plack::Middleware::StatsPerRequest> calculates the duration of a
requests and collects some additonal data like request path, HTTP
method and response status.

You can then use this data to plot some nice graps, find bottlenecks
or set up alerts; or do anything else your stats toolkit supports.

=head2 Configuration

  enable "Plack::Middleware::StatsPerRequest",
      metric_name   => 'http',
      app_name      => 'YourApp',
      path_cleanups => [ \&your_custom_cleanup, \&another_cleanup ],
      add_headers   => [ qw( Accept-Language X-Requested-With )],
      long_request  => 3
  ;

=head3 metric_name

The name of the metric generated. Defaults to C<http_request>.

=head3 app_name

The name of your application. Defaults to C<unknown>.

C<app_name> will be added to each metric as a tag.

=head3 path_cleanups

A list of functions to be called to transform / cleanup the request
path. Defaults to C<[ 'replace_idish' ]>.

Set to an empty list to do no path cleanups. This is not recommended,
unless your statistic tool can normalize paths which might include a
lot of distinct ids etc; or your app does not include ids in its URLs
(maybe they are all passed via query params?)

See L<replace_idish> for more info on the default path cleanup handler.

=head3 add_headers

A list of HTTP header fields. Default to C<[ ]> (empty list).

If you use C<add_headers>, all HTTP headers matching the ones provided
will be added as a tag, with the respective header values as the tag
values.

   enable "Plack::Middleware::StatsPerRequest",
            add_headers => [ 'Accept-Language' ];
   # header_accept-language=Accept-Language

If a header is not sent by a client, a value of C<not_set> will be reported.

=head3 long_request

Requests taking longer than C<long_request> seconds will be logged as
a C<warning>. Defaults to C<5> seconds.

Set to C<0> to turn off.

   enable "Plack::Middleware::StatsPerRequest",
            long_request => 10;
   # curl http://localhost/very/slow/endpoint
   # cat /log/warnings
     Long request, took 23.042: GET /very/slow/endpoint

=head1 SEE ALSO

=over

=item * L<Measure::Everything> is used to actually report the stats

=item * L<Log::Any> is used for logging.

=back

=head1 THANKS

Thanks to

=over

=item *

L<validad.com|https://www.validad.com/> for supporting Open Source.

=back


