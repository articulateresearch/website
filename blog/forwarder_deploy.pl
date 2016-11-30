#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Cwd 'abs_path';
use File::Path 'mkpath';

sub run_command {
    my $command = shift;
    print "Executing: '$command'\n";
    system($command);
    if ($?) {
        if ( $? == -1 ) {
            die "command failed: $!\n";
        }
        else {
            die "command exited with value %d", $? >> 8;
        }
    }
}

sub write_file {
    my ($file, $content) = @_;
    open FILE, ">$file" or die "Can't open file '$file': $!\n";
    print FILE $content
        or die "Can't write to file '$file': $!\n";
    close FILE;
}

my $SplunkPW = '';
my $InstallDIR = '';
my $SplunkPath = '/opt/splunkforwarder';
my $ScriptDIR = abs_path($0);
$ScriptDIR =~ s|/[^/]+$||;
my $SplunkIndexer = 'splunk-indexer.mycorp.com:9997';
my $SplunkDS = 'splunk-ds.mycorp.com:8089';
my $EnableDS = 0;
my $AnswerYes = 0;

print "ScriptDIR = '$ScriptDIR'\n";
GetOptions( 'splunk_pw:s' => \$SplunkPW,
            'splunk_path:s' => \$SplunkPath,
            'install_dir' => \$InstallDIR,
            'splunk_ds:s' => \$SplunkDS,
            'splunk_indexer:s' => \$SplunkIndexer,
            'enableds' => \$EnableDS,
            'answeryes' => \$AnswerYes,
          );

while ( not $SplunkPW ) {
    print 'Splunk Forwarder Password: ';
    $SplunkPW = <STDIN>;
    chomp $SplunkPW;
}

if ( getpwuid($<) ne 'root' ) {
    die "Must run as root. Exiting...";
}

# Find the latest rpm in current dir
my ($SplunkRPM, @others) = `ls -t $ScriptDIR/splunkforwarder*.rpm | head -n 1`;
chomp $SplunkRPM;

if (not $SplunkRPM) {
    die "Can't find any splunk rpm file in '$ScriptDIR'. Please add rpm to same directory of script.\n";
}

if (not $AnswerYes) {
    print "Found '$SplunkRPM', is this correct? [y/N]";
    my $Answer = <STDIN>;
    chomp $Answer;
    if (lc($Answer) ne 'y') {
        print "Exiting...\n";
        exit(-1);
    }
}

if ( -e $SplunkPath ) {
    die "Splunk path '$SplunkPath' already exists! Remove before continuing.\n";
}

if ($InstallDIR) {
    if (not -e $InstallDIR) {
        unless (mkpath($InstallDIR)) {
            die "Couldn't create path '$InstallDIR': $!\n";
        }
    }
    unless (symlink($InstallDIR, $SplunkPath)) {
        die "Couldn't create symlink($InstallDIR, $SplunkPath): $!\n"
    }
}

print "Installing '$SplunkRPM'...\n";
run_command("rpm -ivh $SplunkRPM");

# Make this a slave of the main deployment server
if ( $EnableDS ) {
    print "-enableds specified, setting up deployment client to '$SplunkDS'\n";
    write_file( "$SplunkPath/etc/system/local/deploymentclient.conf", <<"CONFIG");
[deployment-client]

[target-broker:deploymentServer]
    targetUri=$SplunkDS
CONFIG
}

$SplunkBIN = "$SplunkPath/bin/splunk";
run_command("$SplunkBIN start --accept-license");
sleep(2);
run_command("$SplunkBIN stop");
run_command("$SplunkBIN edit user admin -password '$SplunkPW' -auth admin:changeme");
run_command("$SplunkBIN add forward-server $SplunkIndexer");
run_command("$SplunkBIN enable boot-start");
run_command("$SplunkBIN start");
