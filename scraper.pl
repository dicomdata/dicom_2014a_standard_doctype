#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8);
use File::Spec::Functions qw(catfile);
use Net::FTP;
use URI;

# URI of service.
my $base_uri = URI->new('ftp://medical.nema.org/medical/dicom/2014a/source/docbook/');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Connect to FTP.
my $host = $base_uri->host;
my $ftp = Net::FTP->new($host);
if (! $ftp) {
	die "Cannot open '$host' ftp connection.";
}

# Login.
if (! $ftp->login('anonymous', 'anonymous@')) {
	die 'Cannot login.';
}

# Get files.
$ftp->cwd($base_uri->path);
process_files($base_uri->path);

# Process files from FTP.
sub process_files {
	my $path = shift;
	my @files;
	foreach my $file_or_dir ($ftp->ls) {
		my $pwd = $ftp->pwd;
		if (! $ftp->cwd($file_or_dir)) {
			my $file = catfile($path, $file_or_dir);
			print $file."\n";
			save_file($file);
		} else {
			process_files(catfile($path, $file_or_dir));
			$ftp->cwd($pwd);
		}
	}
	return @files;
}

# Save file.
sub save_file {
	my $file = shift;	
	my $part;
	if ($file =~ m/part(\d+)/ms) {
		$part = int($1);
	}
	$dt->insert({
		'Part' => $part,
		'Link' => $base_uri->scheme.'://'.$base_uri->host.$file,
	});
	return;
}
