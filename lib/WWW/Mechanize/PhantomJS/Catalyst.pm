package WWW::Mechanize::PhantomJS::Catalyst;

use 5.10.0;
use Moose;
use IO::Socket::INET;
use Catalyst::EngineLoader;

extends 'WWW::Mechanize::PhantomJS' => { -version => 0.03 };

our $VERSION = '0.01';

has app => (
    is       => 'ro',
    isa      => 'ClassName',
    required => 1,
);

has debug => (
    is  => 'rw',
    isa => 'Bool',
);

has server_pid => (
    is  => 'rw',
    isa => 'Int',
);

has server => (
    is => 'rw',
);

has port => (
    is => 'rw',
    isa => 'Int',
);

sub new
{
    my ($class, @opt) = @_;
    my $self = $class->SUPER::new(@opt);
    my ( $port, $status) = $self->start_catalyst_server;
    if ( $status ne 'ready') {
        print STDERR "[$$] Catalyst server failed to start\n" if $self->debug;
        return undef;
    }
    $self->port($port);
    print STDERR "[$$] Catalyst server started ok\n" if $self->debug;
    return $self;
}

sub DESTROY
{
    my ($self) = @_;
    if ($self->server_pid) {
        print STDERR "[$$] Waiting for Catalyst server [", $self->server_pid, "] to finish..\n" if $self->debug;
        kill 2, $self->server_pid;
        local $SIG{PIPE} = 'IGNORE';
        close $self->server;
    }
    $self->SUPER::DESTROY;
};

sub test_port {
    my ($port) = @_;
    return IO::Socket::INET->new(
        Listen    => 5,
        Proto     => 'tcp',
        Reuse     => 1,
        LocalPort => $port
    ) ? 1 : 0;
}

sub start_catalyst_server {
    my ($self) = @_;

    my $pid;
    if (my $pid = open my $server, '-|') {
        $self->server_pid($pid);
        $self->server($server);
        my $port = <$server>;
        chomp $port;
        my $status = <$server>;
        chomp $status;
        return $port, $status;
    }
    else {
        require Catalyst::ScriptRunner;
        require Catalyst::Script::Server;
        
        my $css_pla = \&Catalyst::Script::Server::_plack_loader_args;
        my $new_css_pla = sub {
            my %args = $css_pla->(@_);
            my $sr = delete $args{server_ready};
            $args{server_ready} = sub {
                print "ready\n"; 
                $sr ? $sr->(@_) : ();
            };
            return %args;
        };
        
        my $css_run = \&Catalyst::Script::Server::_run_application;
        my $new_css_run = sub {
            my $ret;
            eval { $ret = $css_run->(@_); };
            if ( $@ ) {
                my $msg = $@;
                print STDERR "$@\n";
                print "fail\n"; 
                die $@;
            } else {
                return $ret;
            }
        };

        {
            no warnings 'redefine';
            *Catalyst::Script::Server::_plack_loader_args = $new_css_pla;
            *Catalyst::Script::Server::_run_application   = $new_css_run; 
        }

        my ($port, $catalyst) = (4000);
        while (1) {
            $port++, next unless test_port($port);
            print STDERR "[$$] Starting Catalyst server on port $port..\n" if $self->debug;
            print "$port\n";
            @ARGV = ('-p', $port);
            Catalyst::ScriptRunner->run($self->app, 'Server');
	    print STDERR "[$$] Catalyst server exited early, aborting\n" if $self->debug;
	    print "fail\n";
            exit 0;
        }
    }
}

sub get {
    my ($self, $url, %options ) = @_;
    $url = "http://localhost:".$self->port."/$url" unless $url =~ /^http:/;
    return $self->SUPER::get($url, %options);
}

1;

__END__

=pod

=head1 NAME

WWW::Mechanize::PhantomJS::Catalyst - mechanize javascript in your catalyst apps

=head1 DESCRIPTION

A mix of L<WWW::Mechanize::Catalyst> and L<WWW::Mechanize::PhantomJS>, exposed a
WWW::Mechanize API for driving a catalyst server running in the background by PhantomJS/GhostDriver.

=head1 SYNOPSIS

  use WWW::Mechanize::PhantomJS::Catalyst;
  my $mech = WWW::Mechanize::PhantomJS::Catalyst->new(app => 'MyApp');
  $mech->get("/hello.html");

=head1 PREREQUISITES

You'll need PhantomJS v1.9+, and WWW::Mechanize::PhantomJS from here: L<https://github.com/dk/www-mechanize-phantomjs>
( or v0.04 from the official distro when pull requests from github will be incorporated and published).

=head1 AUTHOR

Dmitry Karasik E<lt>dmitry@karasik.eu.orgE<gt>.

=head1 COPYRIGHT

This program is distributed under the standard Perl licence.

Half of the code is borrowed from Stefan Seifert's L<Test::WWW::WebKit::Catalyst>, reused under the same licence.

=cut