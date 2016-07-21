## vROps LB cake
## jsachs
use strict;
use warnings;
use POSIX;
use Cwd;

my %nodes = ();
my $admin_node = 0;
my @months = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
my @info_file = ('status.txt', 'df.txt');
my ($sec, $min, $hour, $day, $month, $year);
my $milli = 0;
my $nodecount = 0;
my $cwd = getcwd();
my $cluster_version = 0;

opendir (my $cdir, $cwd) or die "can't get cwd: $!";
my @ext_dirs = grep { /-extracted$||!\.zip$/ } readdir $cdir;
closedir $cdir;

foreach (@ext_dirs) {

    ## find the admin node ##
    if (/^(.*)_(\d{13})_(\1)/) {
        #print "DEBUG: \$_ =>$_<=\n";
        #print "DEBUG: \$1 =>$1<=\n";
        #print "DEBUG: \$2 =>$2<=\n";
        #print "DEBUG: \$3 =>$3<=\n";
        next unless -d $_;
        next unless $1 eq $3;
        $admin_node = $1;
        $nodes{$1}{'dir'} = "$cwd/$_";
        $nodes{$1}{'admin'} = 1;

        #print "DEBUG: \$admin_node =>$admin_node<=\n";

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

foreach (sort keys %nodes) {
    my $nodename = $_;
    my $nodedir = $nodes{$_}{'dir'};
    my $sysenv_dir = "$nodedir/sysenv";
    my $conf_dir = "$nodedir/conf";
    my $logs_dir = "$nodedir/logs";
    ## slice properties files ##
    my $rolestate_properties
        = "$nodedir/slice-info/conf/utilities/sliceConfiguration/data/roleState.properties";
    my $platformstate_properties
        = "$nodedir/slice-info/conf/utilities/sliceConfiguration/data/platformState.properties";

    ## do node directory processing
    #print "$nodename\n";
    my $vrops_version = read_file("$conf_dir/lastbuildversion.txt");
    $nodes{$nodename}{'version'} = $vrops_version;
    $cluster_version = $vrops_version unless $cluster_version;
    if ($vrops_version eq $cluster_version) {
        $nodes{$nodename}{'offversion'} = 0;
    }
    else {
        # this is bad - nodes are required to be the same version!
        $nodes{$nodename}{'offversion'} = 1;
    }
    #print "$vrops_version\n";

    # Get Instance ID
    $nodes{$nodename}{'instanceid'} =
        get_node_instanceid(read_file($platformstate_properties));

    # Get node roles
    foreach my $roleline (split(/\n/, read_file($rolestate_properties))) {
        if ($roleline =~ /^(\S*)\s*\=\s*(.*?)$/) {
            $nodes{$nodename}{$1} = $2;
        }
    }

    # Get node IP
    $nodes{$nodename}{'ipaddress'} =
        get_node_ipaddress(read_file("$sysenv_dir/ifconfig.txt"));

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
    #print "$cpu_count X $cpu_name\n";
    $nodes{$nodename}{'cpu_count'} = $cpu_count;
    $nodes{$nodename}{'cpu_name'} = $cpu_name;

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

    #print "$mem_total GB RAM / $mem_free GB free\n$swap_total GB swap / $swap_free GB free\n\n";
    $nodes{$nodename}{'mem_total'} = $mem_total;
    $nodes{$nodename}{'mem_free'} = $mem_free;
    $nodes{$nodename}{'swap_total'} = $swap_total;
    $nodes{$nodename}{'swwap_free'} = $swap_free;


    #foreach (@info_file) {
    #    my $info = read_file("$sysenv_dir/$_");
    #    $info =~ s/^(?:.*\n){1,4}//;
    #    print $info;
    #    print "\n";
    #}

}

# node report
print "$cluster_version\n";
foreach my $node (sort keys %nodes) {
    my $instanceid = $nodes{$node}{'instanceid'};
    my $ipaddress = $nodes{$node}{'ipaddress'};
    print "$node\t$instanceid\t$ipaddress\n";
    if ($nodes{$node}{'offversion'}) {
        print "!\t" . $nodes{$node}{'version'} . "\n";
    }
    if (!$nodes{$node}{'sliceonline'}) {
        print "!OFFLINE:\t" . $nodes{$node}{'offlinereason'} . "\n";
    }
}

# dump node hashes for debugging
#foreach my $node (sort keys %nodes) {
#    print "$node\n";
#    foreach my $nprop (sort keys %{$nodes{$node}}) {
#        print "\t=>$nprop<=\t=>" . $nodes{$node}{$nprop} . "<=\n";
#    }
#}

sub read_file {
    my ($filename) = @_;
 
    open my $in, '<:encoding(UTF-8)', $filename or die "Could not open '$filename' for reading $!";
    local $/ = undef;
    my $all = <$in>;
    close $in;
 
    return $all;
}

sub get_node_instanceid {
    my $platformstate = shift;
    my $instanceid = '';

    if ($platformstate =~ /slicedinstanceid = (.*?)\n/) {
        $instanceid = $1;
    }
    else {
        $instanceid = 'could not find instance ID';
    }

    return $instanceid;
}

sub get_node_ipaddress {
    my $ifconfig = shift;
    my $ipaddress = '';
    my $record = 0;

    foreach (split(/\n/, $ifconfig)) {
        $record = 1 if /^eth/;
        next unless $record;
        #print "DEBUG: =>$_<=\n";
        if (/inet addr:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/) {
            $ipaddress = $1;
            last;
        }
    }

    return $ipaddress;
}
