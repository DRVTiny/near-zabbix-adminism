#!/usr/bin/perl
use strict;
use warnings;
use 5.16.1;
use constant {
	DFLTS_CONFIG 		=>  $ENV{'HOME'} . '/.mailer_defaults.json',
	DFLTS_SMTP_AUTH_TYPE	=> 'NTLM',
	MIME_TYPE_MULTIPART 	=> 'multipart/mixed',
	VERY_DFLT_SUBJ		=> 'See your file inside',
	FROM 			=>  0,
	TO			=>  1,
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
use Net::SMTP_auth;



# MIME::Lite->send('smtp','some.host', AuthUser=>$user, AuthPass=>$pass);


my ($opt, $usage) = describe_options(
	'%c %o',
	['config|c=s', 	'Path to config file', {'default' => DFLTS_CONFIG}],
	['subject|S=s', 'Mail subject (default: config value will be used)'],
	['from|f=s',	'Mail from (default: config value will be used)'],
	['to|t=s',	'Mail to (default: config value will be used)'],
	['smtp-server|M=s', 'SMTP server to use (default: config value will be used)'],
	['mime-type=s',	 'MIME type of the attached file'],
	['as-text|T',	'Do not attach, send it as embedded text'],
	
	[],
	
	['dry-run|Y', 	'Dry run, i.e. do not send anything'],
	['debug|x', 	'Turn on eXtensive[verbose] tracing and debugging'],
	['help|h',	'Show this help message'],
	{
		'show_defaults' => 1
	}
);

if ( $opt->help ) {
	print $usage->text;
	exit
}

my ($flDebug, $flDryRun) = ($opt->debug, $opt->dry_run);

my $configPath = $opt->config;
my $config = read_config($configPath);

my $dflts4send = $config->{'mail_types'}{'send_file'} 
	or die 'failed to read <<mail_types.send_file>> defaults from the specified config file ', $configPath;

my $from 	= $opt->from || $dflts4send->{'dflt_from'} 
	or die 'sender not specified (command-line option or config parameter)';
my $to 		= $opt->to   || $dflts4send->{'dflt_to'}
	or die 'recipient not specified (command-line option or config parameter)';;
say "from=$from, to=$to" if $flDebug;


my $authConf = $config->{'smtp'}{'auth'};
my $smtpServer = $opt->smtp_server || $config->{'smtp'}{'server'}
	or die 'SMTP server must be specified (command-line option or config parameter)';
my $smtp = Net::SMTP_auth->new($smtpServer, 'Debug' => $flDebug);
my $authType = $authConf->{'type'};
$smtp->auth($authType, @{$authConf}{qw'login password'})
	or die $authType, ' auth failed';


my @from_to = ($from, $to);
MIME::Lite->send(
	'sub' => sub {
		my ($msg, $from_to) = @_;
		
		/@/ or die 'invalid send arguments' for @{$from_to};
		my $from = $from_to->[FROM];
		my @to = ref($from_to->[TO]) eq 'ARRAY' 
				? @{$from_to->[TO]}
				: split /(?:\s*,\s*|(?:\s*\r?\n\s*)+)/ => $from_to->[TO];
		for my $single_to ( @to ) {
			$smtp->mail($from);
			$smtp->to($single_to);
			
			$smtp->data();
			$smtp->datasend($_ . "\n") for split /\r?\n/ => $msg->as_string;
			$smtp->dataend
		}
		
		$smtp->quit
	},
	\@from_to
);

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
			say STDERR 'STDIN will be used as input' if $flDebug;
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
			say STDERR 'STDIN will be used as input' if $flDebug;
			my ($fh, $fname) = tempfile();
			print $fh do { local $/ = <STDIN> };
			close $fh;
			$fname
		} else {
			$ARGV[0]
		}
	};
	( -e $file_name ) or die "we intended to send $file_name, but is does not exists :(\n";
	-z $file_name and die "failed to send empty file\n";
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

sub read_config {
	state $j;
	my $config = shift;
	length($config) or die 'failed to accept empty string as a configuration file path';
	($j //= JSON->new)->decode(do {
		open my $fh, '<', $config
			or die 'failed to open configuration file ', $config, ': ', $!;
		local $/ = readline $fh
	})
}

=doc
Sample config file:
{
	"smtp": {
		"server": "xxx.yyy.zzz.jjj",
		"auth": {
			"login": "mymaillogin",
			"password": "mypassword",
			"type": "NTLM"
		}
	},
	"mime": {
		"fallback_type": "application/octet-stream"
	},
	"mail_types": {
		"send_file": {
			"subject": "Test mail",
			"dflt_from": "mymaillogin@example.com",
			"dflt_to": "mymaillogin@example.com"	
		},
		"ping": {
			"mail_from": "ping@example.com",
			"send_to": "ping@example.com",
			"subject": "PING"
		}
	}
}
