#!/usr/bin/perl
use strict;
use warnings;
use 5.16.1;
use constant {
	DFLTS_CONFIG 		=> $ENV{'HOME'} . '/.mailer_defaults.json',
	MIME_TYPE_MULTIPART 	=> 'multipart/mixed',
	VERY_DFLT_SUBJ		=> 'See your file inside',
};
use Getopt::Long::Descriptive;
use Mail::Send;

use MIME::Lite;
use File::LibMagic;
use File::Basename	qw( basename );
use File::Temp		qw( tempfile );
use File::Slurp		qw( read_file );
use JSON;
use Data::Dumper;

my $config = 
	( -e DFLTS_CONFIG)
		? read_config(DFLTS_CONFIG)
		: {};

sub read_config {
	state $j;
	my $config = shift;
	($j //= JSON->new)->decode(do {
		open my $fh, '<', $config
			or die 'failed to open config ', $config, ': ', $!;
		local $/ = readline $fh
	})
}
# MIME::Lite->send('smtp','some.host', AuthUser=>$user, AuthPass=>$pass);
my $dflts4send = $config->{'mail_types'}{'send_file'} 
	or die 'failed to read <<mail_types.send_file>> defaults from the specified config file ' . DFLTS_CONFIG();

my ($opt, $usage) = describe_options(
	'%c %o',
	['subject|S=s', 'Mail subject',	{'default' => $dflts4send->{'subject'}}],
	['from|f=s',	'Mail from',	{'default' => $dflts4send->{'dflt_from'}}],
	['to|t=s',	'Mail to',	{'default' => $dflts4send->{'dflt_to'}}],
	['smtp-server|M=s', 'SMTP server to use', {'default' => $config->{'smtp'}{'server'}}],
	['mime-type=s',	 'MIME type of the attached file'],
	['as-text|T',	'Do not attach, send it as embedded text'],
	
	[],
	
	['dry-run|Y', 	'Dry run, i.e. do not send anything'],
	['debug|x', 	'Turn on eXtensive[verbose] tracing and debugging'],
	['help|h',	'Show this help message'],
);

if ( $opt->help ) {
	print $usage->text;
	exit
}

my ($flDebug, $flDryRun) = ($opt->debug, $opt->dry_run);

my $authConf = $config->{'smtp'}{'auth'};
MIME::Lite->send(
	'smtp' => $opt->smtp_server, 
	'Debug' => $flDebug,
	$authConf ? ('AuthUser' => $authConf->{'login'}, 'AuthPass' => $authConf->{'password'}) : ()
);

my $from = $opt->from || $opt->to;
my $to = $opt->to || $opt->from;
say "from=$from, to=$to" if $flDebug;
unless ($from and $to) {
	die 'we dont know recepient or sender, so fail to proceed'
}

my $msg;
my %common_msg_opts = (
	From    => $from,
	To      => $to,
	Subject => $opt->subject || VERY_DFLT_SUBJ,
);

if ( $opt->as_text ) {
	my $text = do {
		if (defined $ARGV[0] && $ARGV[0] ne '-') {
			my $cmdl_arg = $ARGV[0];
			if ( $cmdl_arg =~ /^\@/ ) {
				open my $fh, '<', substr($cmdl_arg, 1) 
					or die 'failed to open file mentioned in body: ', $!;
				local $/; <$fh>
			} else {
				$cmdl_arg =~ s%^\\@%@%r
			}
		} else {
			local $/;
			<STDIN>
		}
	};
	$msg = MIME::Lite->new(
		%common_msg_opts,
		Data	=> $text
        )
} else {
	my $file_name = do {
		if (! defined $ARGV[0] || $ARGV[0] eq '-') {
			my ($fh, $fname) = tempfile();
			say $fh do { local $/ = <STDIN> };
			close $fh;
			$fname
		} else {
			$ARGV[0]
		}
	};
	$msg = MIME::Lite->new(
		%common_msg_opts,
		Type	=> MIME_TYPE_MULTIPART,
	);
	my $opt_mime_type = $opt->mime_type;
	my $file_mime_type = 
		 $opt_mime_type && $opt_mime_type ne 'guess'
		 	? $opt_mime_type
		 	: det_mime_type($file_name) // $config->{'mime'}{'fallback_type'};
	say STDERR 'Determined file MIME-type: ', $file_mime_type if $flDebug;
	$msg->attach(
            Type     => $file_mime_type,
            Path     => $file_name,
            Filename => basename($file_name),
            Disposition => 'attachment'		
	);
}

if ( $flDryRun ) {
	$msg->print(\*STDERR)
} else {
	$msg->send
}

sub det_mime_type {
	state $magic = File::LibMagic->new;
	my $file = $_[0];
	my ($method, $what2check) = 
		ref($file) eq 'GLOB'
			? ('info_from_handle', $file)
			: ('info_from_string', scalar(read_file $file));
			
	my $mt_content = $magic->$method($what2check)->{'mime_type'};
	
	$mt_content =~ m%text/plain% && ref($file) ne 'GLOB'
		? $magic->info_from_filename($file)->{'mime_type'}
		: $mt_content
}

=doc
~/.mailer_defaults.json config example:
{
	"smtp": {
		"server": "10.10.1.8",
		"auth": {
			"login": "my_login",
			"password": "some_password"
		}
	},
	"mime": {
		"fallback_type": "application/octet-stream"
	},
	"mail_types": {
		"send_file": {
			"subject": "Test mail",
			"dflt_from": "mу@domain.com",
			"dflt_to": "mу@domain.com"
		},
		"ping": {
			"mail_from": "alerts@domain.com",
			"send_to": "alerts@domain.com",
			"subject": "PING"
		}
	}
}

