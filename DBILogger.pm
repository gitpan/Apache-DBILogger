package Apache::DBILogger;

require 5.004;
use strict;
use Apache::Constants qw( :common );
use DBI;
use Date::Format;

$Apache::DBILogger::revision = sprintf("%d.%02d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/o);
$Apache::DBILogger::VERSION = "0.83";

sub reconnect($$) {
	my ($dbhref, $r) = @_;

	$r->log_error("Reconnecting to DBI server");

	$$dbhref = DBI->connect($r->dir_config("DBILogger_data_source"), $r->dir_config("DBILogger_username"), $r->dir_config("DBILogger_password"));
  
  	unless ($$dbhref) { 
  		$r->log_error("Apache::DBILogger could not connect to ".$r->dir_config("DBILogger_data_source")." - ".$DBI::errstr);
  		return DECLINED;
  	}
}

sub logger {
	my $r = shift;
 
	#$r->bytes_sent || return OK;
 
	my $s = $r->server;
	my $c = $r->connection;

	my %data = (
		'server'	=> $s->server_hostname,
 		'bytes'		=> $r->bytes_sent,
		'filename'	=> $r->filename,
		'remotehost'=> $c->remote_host,
		'remoteip'  => $c->remote_ip,
		'status'    => $r->status,
		'urlpath'	=> $r->uri,
		'referer'	=> $r->header_in("Referer") || '',	
    	'useragent'	=> $r->header_in('User-Agent'),
    	'timeserved'=> time2str("%Y-%m-%d %X", time)
	);

	if (my $user = $c->user) {
		$data{user} = $user;
	}

	my $dbh = DBI->connect($r->dir_config("DBILogger_data_source"), $r->dir_config("DBILogger_username"), $r->dir_config("DBILogger_password"));
  
  	unless ($dbh) { 
  		$r->log_error("Apache::DBILogger could not connect to ".$r->dir_config("DBILogger_data_source")." - ".$DBI::errstr);
  		return DECLINED;
  	}
  	
  	my @valueslist;
  	
  	foreach (keys %data) {
		$data{$_} = $dbh->quote($data{$_});
		push @valueslist, $data{$_};
	}
	
	my $statement = "insert into requests (". join(',', keys %data) .") VALUES (". join(',', @valueslist) .")";

	my $tries = 0;
	
  	TRYAGAIN: my $sth = $dbh->prepare($statement);
  	
  	unless ($sth) {
  		$r->log_error("Apache::DBILogger could not prepare sql query ($statement): $DBI::errstr");	
  		return DECLINED;
  	}

	my $rv = $sth->execute;

	unless ($rv) {
		$r->log_error("Apache::DBILogger had problems executing query ($statement): $DBI::errstr");
		unless ($tries++ > 1) {
			&reconnect(\$dbh, $r);
			goto TRYAGAIN;
		}
	}
	
	$sth->finish;


	$dbh->disconnect;

	OK;
}

# #perl pun: <q[merlyn]> windows is for users who can't handle the power of the mac.

sub handler { 
	shift->post_connection(\&logger)
}

1;
__END__

=head1 NAME

Apache::DBILogger - Tracks what's being transferred in a DBI database

=head1 SYNOPSIS

  # Place this in your Apache's httpd.conf file
  PerlLogHandler Apache::DBILogger

  PerlSetVar DBILogger_data_source    DBI:mysql:httpdlog
  PerlSetVar DBILogger_username       httpduser
  PerlSetVar DBILogger_password       secret
  
Create a database with a table named B<requests> like this:

CREATE TABLE requests (
  id mediumint(9) DEFAULT '0' NOT NULL auto_increment,
  server varchar(127) DEFAULT '' NOT NULL,
  bytes mediumint(9) DEFAULT '0' NOT NULL,
  user varchar(15),
  filename varchar(200),
  remotehost varchar(150),
  remoteip varchar(15) DEFAULT '' NOT NULL,
  status smallint(6) DEFAULT '0' NOT NULL,
  timeserved datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
  urlpath varchar(200) DEFAULT '' NOT NULL,
  referer varchar(250),
  useragent varchar(250),
  PRIMARY KEY (id),
  KEY server_idx (server)
);

Its recommended that you include

use Apache::DBI;
use DBI;
use Apache::DBILogger;

in your startup.pl script. Please read the Apache::DBI documentation for
further information.

=head1 DESCRIPTION

This module tracks what's being transfered by the Apache web server in a 
SQL database (everything with a DBI/DBD driver).  This allows to get 
statistics (of almost everything) without having to parse the log
files (like the Apache::Traffic module, just in a "real" database, and with
a lot more logged information).

After installation, follow the instructions in the synopsis and restart 
the server.
	
The statistics are then available in the database. See the section VIEWING
STATISTICS for more details.

=head1 PREREQUISITES

You need to have compiled mod_perl with the LogHandler hook in order
to use this module. Additionally, the following modules are required:

	o DBI
	o Date::Format

=head1 INSTALLATION

To install this module, move into the directory where this file is
located and type the following:

        perl Makefile.PL
        make
        make test
        make install

This will install the module into the Perl library directory. 

Once installed, you will need to modify your web server's configuration
file so it knows to use Apache::DBILogger during the logging phase.

=head1 VIEWING STATISTICS

I haven't made any pretty scripts og web interfaces to the log-database yet,
so you're on your own.  :-)

For a start try:

=over 4

=item hit count and total bytes transfered from the virtual server www.company.com

C<select count(id),sum(bytes) from requests where server="www.company.com">


=item hit count and total bytes from all servers, ordered by number of hits
 
C<select server,count(id) as hits,sum(bytes) from requests group by server order by hits desc>


=item count of hits from macintosh users

C<select count(id) from requests where useragent like "%Mac%">


=item hits and total bytes in the last 30 days

C<select count(id),sum(bytes)  from requests where server="www.company.com" and TO_DAYS(NOW()) - TO_DAYS(timeserved) <= 30>


=item hits and total bytes from www.company.com on mondays.

C<select count(id),sum(bytes)  from requests where server="www.company.com" and dayofweek(timeserved) = 2>


=back

See your sql server documentation of more examples. I'm a happy mySQL user,
so I would continue on 

http://www.tcx.se/Manual_chapter/manual_toc.html

=head1 SUPPORT

This module is supported via the mod_perl mailinglist (modperl@listproc.itribe.net).

I would like to know which databases this module have been tested on, so please mail me
if you try it.

=head1 AUTHOR

Copyright (C) 1998, Ask Bjoern Hansen <ask@netcetera.dk>. All rights reserved.

This module is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1), mod_perl(3)


=cut
