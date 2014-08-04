#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Digest::MD5;
use Encode qw(decode_utf8);
use English;
use File::Spec::Functions qw(catfile);
use File::Temp qw(tempfile);
use LWP::UserAgent;
use Net::FTP;
use URI;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

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

# Get link and compute MD5 sum.
sub md5 {
	my $link = shift;
	my (undef, $temp_file) = tempfile();
	my $ua = LWP::UserAgent->new(
		'agent' => 'Mozilla/5.0',
	);
	my $get = $ua->get($link, ':content_file' => $temp_file);
	my $md5_sum;
	if ($get->is_success) {
		my $md5 = Digest::MD5->new;
		open my $temp_fh, '<', $temp_file;
		$md5->addfile($temp_fh);
		$md5_sum = $md5->hexdigest;
		close $temp_fh;
		unlink $temp_file;
	}
	return $md5_sum;
}

# Process files from FTP.
sub process_files {
	my $path = shift;
	my @files;
	foreach my $file_or_dir ($ftp->ls) {
		my $pwd = $ftp->pwd;
		if (! $ftp->cwd($file_or_dir)) {
			my $file = catfile($path, $file_or_dir);
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
	my $link = $base_uri->scheme.'://'.$base_uri->host.$file;
	my $ret_ar = eval {
		$dt->execute('SELECT COUNT(*) FROM data '.
			'WHERE Link = ?', $link);
	};
	if ($EVAL_ERROR || ! @{$ret_ar}
		|| ! exists $ret_ar->[0]->{'count(*)'}
		|| ! defined $ret_ar->[0]->{'count(*)'}
		|| $ret_ar->[0]->{'count(*)'} == 0) {

		my $md5 = md5($link);
		if (! defined $md5) {
			print "Cannot get document for $link.\n";
		} else {
			if (defined $part) {
				print "Part $part: ";
			}
			print "$link\n";
			$dt->insert({
				'Part' => $part,
				'Link' => $link,
				'MD5' => $md5,
			});
			# TODO Move to begin with create_table().
			$dt->create_index(['MD5'], 'data', 1, 0);
		}
	}
	return;
}
