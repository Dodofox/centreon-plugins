#
# Copyright 2016 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package database::mssql::mode::databasessize;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

my $instance_mode;

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'database', type => 1, cb_prefix_output => 'prefix_database_output', message_multiple => 'All databases are OK' },
    ];

    $self->{maps_counters}->{database} = [
        { label => 'database', set => {
                key_values => [ { name => 'prct_used' }, { name => 'used' }, { name => 'free' }, { name => 'total' }, { name => 'display' } ],
                closure_custom_calc => \&custom_usage_calc,
                closure_custom_output => \&custom_usage_output,
                closure_custom_perfdata => \&custom_usage_perfdata,
                closure_custom_threshold_check => \&custom_usage_threshold,
            }
        },
    ];
}

sub custom_usage_perfdata {
    my ($self, %options) = @_;

    my $label = 'db_' . $self->{result_values}->{display} . '_used';
    my $value_perf = $self->{result_values}->{used};
    if (defined($instance_mode->{option_results}->{free})) {
        $label = 'db_' . $self->{result_values}->{display} . '_free';
        $value_perf = $self->{result_values}->{free};
    }
    my $extra_label = '';
    $extra_label = '_' . $self->{result_values}->{display} if (!defined($options{extra_instance}) || $options{extra_instance} != 0);
    my %total_options = ();
    if ($instance_mode->{option_results}->{units} eq '%') {
        $total_options{total} = $self->{result_values}->{total};
        $total_options{cast_int} = 1;
    }

    $self->{output}->perfdata_add(label => $label . $extra_label, unit => 'B',
                                  value => $value_perf,
                                  warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{label}, %total_options),
                                  critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{label}, %total_options),
                                  min => 0, max => $self->{result_values}->{total});
}

sub custom_usage_threshold {
    my ($self, %options) = @_;

    my ($exit, $threshold_value);
    $threshold_value = $self->{result_values}->{used};
    $threshold_value = $self->{result_values}->{free} if (defined($instance_mode->{option_results}->{free}));
    if ($instance_mode->{option_results}->{units} eq '%') {
        $threshold_value = $self->{result_values}->{prct_used};
        $threshold_value = $self->{result_values}->{prct_free} if (defined($instance_mode->{option_results}->{free}));
    }
    $exit = $self->{perfdata}->threshold_check(value => $threshold_value, threshold => [ { label => 'critical-' . $self->{label}, exit_litteral => 'critical' }, { label => 'warning-'. $self->{label}, exit_litteral => 'warning' } ]);
    return $exit;
}

sub custom_usage_output {
    my ($self, %options) = @_;

    my ($total_size_value, $total_size_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{total});
    my ($total_used_value, $total_used_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{used});
    my ($total_free_value, $total_free_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{free});
    my $msg = sprintf("Total: %s Used: %s (%.2f%%) Free: %s (%.2f%%)",
                   $total_size_value . " " . $total_size_unit,
                   $total_used_value . " " . $total_used_unit, $self->{result_values}->{prct_used},
                   $total_free_value . " " . $total_free_unit, $self->{result_values}->{prct_free});
    return $msg;
}

sub custom_usage_calc {
    my ($self, %options) = @_;

    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    $self->{result_values}->{total} = $options{new_datas}->{$self->{instance} . '_total'};
    $self->{result_values}->{used} = $options{new_datas}->{$self->{instance} . '_used'};
    $self->{result_values}->{prct_used} = $options{new_datas}->{$self->{instance} . '_prct_used'};
    $self->{result_values}->{free} = $options{new_datas}->{$self->{instance} . '_free'};

    $self->{result_values}->{prct_free} = 100 - $self->{result_values}->{prct_used};

    return 0;
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                "filter-database:s"   => { name => 'filter_database' },
                                "units:s"             => { name => 'units', default => '%' },
                                "free"                => { name => 'free' },
                                });
    return $self;
}

sub prefix_database_output {
    my ($self, %options) = @_;

    return "Database '" . $options{instance_value}->{display} . "' ";
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $instance_mode = $self;
}

sub manage_selection {
    my ($self, %options) = @_;
    # $options{sql} = sqlmode object
    $self->{sql} = $options{sql};
    $self->{sql}->connect();
    $self->{sql}->query(query => q{DBCC SQLPERF(LOGSPACE)});

    my $result = $self->{sql}->fetchall_arrayref();

    my @databases_selected;
    foreach my $row (@$result) {
        next if (defined($self->{option_results}->{filter_database}) && $$row[0] !~ /$self->{option_results}->{filter_database}/);
        push @databases_selected, $$row[0];
    }

    foreach my $database (@databases_selected) {
        $self->{sql}->query(query => "use [$database]; 
        
    WITH DatabaseSizeInfos
    AS (
        SELECT
        @\@servername as [Server Name],
        DB_NAME() AS [Database Name]
        , convert(decimal(12,2),round(a.size/128.000,2)) as [Allocated Size in MB]
        , CONVERT(VARCHAR(50), convert(decimal(12,2),round(fileproperty(a.name,'SpaceUsed')/128.000,2)))  as [Space Used in MB]
        , CONVERT(VARCHAR(50), convert(decimal(12,2),round((a.size-fileproperty(a.name,'SpaceUsed'))/128.000,2)))  as [Free Space in MB]
        , CAST(100 * (CAST (((a.size/128.0 -CAST(FILEPROPERTY(a.name,'SpaceUsed' ) AS int)/128.0)/(a.size/128.0)) AS decimal(4,2))) AS decimal(4,2)) AS [Free Space Percent] 
        ,
        CASE is_percent_growth
            WHEN 1 THEN CONVERT(VARCHAR(5),growth)
            ELSE CONVERT(VARCHAR(20),(growth/128))
        END [Autogrow Value]
        ,
        CASE max_size
            WHEN -1 THEN
                CASE growth
                    WHEN 0 THEN convert(decimal(12,2),round(a.size/128.000,2)) -- if restricted MaxSize = CurrentAllocatedSpace 
                    ELSE  268435456 -- 2TB max size if Unlimited
                END
            ELSE max_size/128
        END [Max Size in MB]
        ,
        CASE max_size
            WHEN -1 THEN
                CASE growth
                    WHEN 0 THEN convert(decimal(12,2),round(a.size-fileproperty(a.name,'SpaceUsed')/128.000,2)) 
                    ELSE 268435456 -- 2TB max size if Unlimited  
                END
            ELSE CAST([max_size]/128.0-(FILEPROPERTY(a.name,'SpaceUsed' )/128.0) AS DECIMAL(10,2))
        END [Max Available Space in MB]
        ,
        CAST((CAST(FILEPROPERTY(a.name,'SpaceUsed' )/128.0 AS DECIMAL(10,2))/CAST([max_size]/128.0 AS DECIMAL(10,2)))*100 AS DECIMAL(10,2)) AS [Max Percent Used]
        from sys.database_files a
        WHERE type = 0 -- Only data files
    )

    SELECT  [Database Name],
        CONVERT(VARCHAR(50), SUM([Allocated Size in MB])) + ' MB' [Allocated Size in MB],
        CONVERT(VARCHAR(50), SUM([Max Available Space in MB])) + ' MB' [Max Available Space in MB],
        CONVERT(VARCHAR(50), SUM([Max Size in MB])) + ' MB'  Max_Size_MB
    from DatabaseSizeInfos
    group by [Database Name] 
        ;");
        my $result2 = $self->{sql}->fetchall_arrayref();
        foreach my $row (@$result2) {
            my $size_brut = $$row[3];
            my $size = convert_bytes($size_brut);
            my $free_brut = $$row[2];
            my $free = convert_bytes($free_brut);
            my $used = $size - $free;
            my $percent_used = ($used / $size) * 100;

            $self->{database}->{$database} = {  used => $used,
                                                free => $free,
                                                total => $size,
                                                prct_used => $percent_used,
                                                display => lc $database };

        }
    }
}

sub convert_bytes {
    my ($brut) = @_;
    my ($value,$unit) = split(/\s+/,$brut);
    if ($unit =~ /kb*/i) {
        $value = $value * 1024;
    } elsif ($unit =~ /mb*/i) {
        $value = $value * 1024 * 1024;
    } elsif ($unit =~ /gb*/i) {
        $value = $value * 1024 * 1024 * 1024;
    } elsif ($unit =~ /tb*/i) {
        $value = $value * 1024 * 1024 * 1024 * 1024;
    }
    return $value;
}

1;

__END__

=head1 MODE

Check MSSQL Database usage

=over 8

=item B<--warning-database>

Threshold warning.

=item B<--critical-database>

Threshold critical.

=item B<--filter-database>

Filter database by name. Can be a regex

=item B<--units>

Default is '%', can be 'B'

=item B<--free>

Perfdata show free space

=back

=cut
