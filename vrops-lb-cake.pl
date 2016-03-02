## vROps LB cake
## jsachs
use strict;
use warnings;
use POSIX;
use Cwd;
use Data::Dumper;

my %nodes = ();
my $admin_node = 0;
my @months = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
my @info_file = ('status.txt', 'df.txt');
my ($sec, $min, $hour, $day, $month, $year);
my $milli = 0;
my $nodecount = 0;
my $cwd = getcwd();

opendir (my $cdir, $cwd) or die "can't get cwd: $!";
my @ext_dirs = grep { /-extracted$||!\.zip$/ } readdir $cdir;
closedir $cdir;

foreach (@ext_dirs) {

    ## find the admin node ##
    if (/(.*)_(\d{13})_\1/) {
        next unless -d $_;
        $admin_node = $1;
        $nodes{$1}{'dir'} = "$cwd/$_";
        $nodes{$1}{'admin'} = 1;

        print "DEBUG: \$admin_node =>$admin_node<=\n";
        print "DEBUG: \$_ =>$_<=\n";

        ## extract the timestamp from the directory name
        ## and convert it to human readable form
        ## only perform this once (unless there are multime timestamps in
        ## a single log bundle which should probably not happen)
        $milli = $2;
        my $epoch = $milli;
        $epoch =~ s/\d{3}$//;
        #print"DEBUG: epoch: =>$epoch<=\n";
        ($sec, $min, $hour, $day, $month, $year) = (localtime($epoch))[0,1,2,3,4,5];
        foreach ($hour, $min, $sec) {
            $_ = "0$_" unless length($_) > 1;
        }

        print "Log Bundle Time: ".$months[$month]." ".$day.", ".($year+1900)." $hour:$min:$sec ";
        print strftime("%Z", localtime()) . "\n";

        last;
    }

}

die "did not find admin node directory!" unless $admin_node;

# Get the non-admin nodes in the cluster
foreach (@ext_dirs) {

    next if /^($admin_node|cluster)/;
    if (/^(.*)_($milli)_($admin_node)/) {
        next unless -d $_;
        $nodes{$1}{'dir'} = "$cwd/$_";
        $nodes{$1}{'admin'} = 0;
    }

}


#print Dumper(\%nodes);
#exit;

foreach (sort keys %nodes) {
    my $nodename = $_;
    my $nodedir = $nodes{$_}{'dir'};
    my $sysenv_dir = "$nodedir/sysenv";
    my $conf_dir = "$nodedir/conf";
    my $logs_dir = "$nodedir/logs";

    ## do node directory processing
    print "$nodename\n";
    my $vrops_version = read_file("$conf_dir/lastbuildversion.txt");
    print "$vrops_version\n";

    # CPU
    my $cpu_count = 0;
    my $cpu_name = 'CPU MODEL NAME NOT FOUND!';
    my $cpuinfotxt = "$sysenv_dir/cpuInfo.txt";
    $cpuinfotxt = "$sysenv_dir/cpuinfo.txt" unless -e $cpuinfotxt; 
    my $cpuinfo = read_file($cpuinfotxt);
    foreach my $line (split(/\n/, $cpuinfo)) {
        $cpu_count++ if $line =~ /^processor/;
        if ($line =~ /^model name\s*: (.*)$/) {
            $cpu_name = $1;
        }
    }
    print "$cpu_count X $cpu_name\n";

    # RAM
    my ($mem_total, $mem_free, $swap_total, $swap_free) = (0, 0, 0, 0);
    my $meminfotxt = "$sysenv_dir/memInfo.txt";
    $meminfotxt = "$sysenv_dir/meminfo.txt" unless -e $meminfotxt;
    my $meminfo = read_file($meminfotxt);
    foreach my $line (split(/\n/, $meminfo)) {
        if ($line =~ /^MemTotal:\s*(\d+) kB/) {
            $mem_total = $1;
        }
        if ($line =~ /^MemFree:\s*(\d+) kB/) {
            $mem_free = $1;
        }
        if ($line =~ /^SwapTotal:\s*(\d+) kB/) {
            $swap_total = $1;
        }
        if ($line =~ /^SwapFree:\s*(\d+) kB/) {
            $swap_free = $1;
        }
    }
    # format values to GB and round to 2 places after the decimal
    foreach ($mem_total, $mem_free, $swap_total, $swap_free) {
        $_ = $_/1024/1024;
        $_ = sprintf("%.2f", $_);
    }

    print "$mem_total GB RAM / $mem_free GB free\n$swap_total GB swap / $swap_free GB free\n\n";


    foreach (@info_file) {
        my $info = read_file("$sysenv_dir/$_");
        $info =~ s/^(?:.*\n){1,4}//;
        print $info;
        print "\n";
    }

}


sub read_file {
    my ($filename) = @_;
 
    open my $in, '<:encoding(UTF-8)', $filename or die "Could not open '$filename' for reading $!";
    local $/ = undef;
    my $all = <$in>;
    close $in;
 
    return $all;
}
