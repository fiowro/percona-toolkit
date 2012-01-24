# This program is copyright 2011 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# MySQLStatusWaiter package
# ###########################################################################
{
# Package: MySQLStatusWaiter
# MySQLStatusWaiter helps limit server load by monitoring status variables.
package MySQLStatusWaiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Required Arguments:
#   spec       - Arrayref of status variables to monitor.
#   get_status - Callback passed variable, returns variable's value.
#   sleep      - Callback to sleep between checking variables.
#   oktorun    - Callback that returns true if it's ok to continue running.
#
# Returns:
#   MySQLStatusWaiter object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(spec get_status sleep oktorun);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $max_val_for = _parse_spec(%args);

   my $self = {
      get_status  => $args{get_status},
      sleep       => $args{sleep},
      oktorun     => $args{oktorun},
      max_val_for => $max_val_for,
   };

   return bless $self, $class;
}

# Sub: _parse_spec
#   Parse a list of variables to monitor.
#
# Required Arguments:
#   spec       - Arrayref of var(=val) strings to monitor.
#   get_status - Callback passed variable, returns variable's value.
#
# Returns:
#   Hashref with each variable's maximum permitted value.
sub _parse_spec {
   my ( %args ) = @_;
   my @required_args = qw(spec get_status);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($spec, $get_status) = @args{@required_args};

   if ( !@$spec ) {
      PTDEBUG && _d('No spec, disabling status var waits');
      return;
   }

   my %max_val_for;
   foreach my $var_val ( @$spec ) {
      my ($var, $val) = split /[:=]/, $var_val;
      die "Invalid spec: $var_val" unless $var;
      if ( !$val ) {
         my $init_val = $get_status->($var);
         PTDEBUG && _d('Initial', $var, 'value:', $init_val);
         $val = int(($init_val * .20) + $init_val);
      }
      PTDEBUG && _d('Wait if', $var, '>=', $val);
      $max_val_for{$var} = $val;
   }

   return \%max_val_for; 
}

# Sub: max_values
#   Return a hashref with each variable's maximum permitted value.
sub max_values {
   my ($self) = @_;
   return $self->{max_val_for};
}

# Sub: wait
#   Wait until all variables' values are less than their permitted maximums.
#
# Optional Arguments:
#   Progress - <Progress> object to report waiting
sub wait {
   my ( $self, %args ) = @_;

   # No vars?  Nothing to monitor; return immediately.
   return unless $self->{max_val_for};

   my $pr = $args{Progress}; # optional

   my $oktorun    = $self->{oktorun};
   my $get_status = $self->{get_status};
   my $sleep      = $self->{sleep};
   
   my %vals_too_high = %{$self->{max_val_for}};
   my $pr_callback;
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         print STDERR "Pausing because "
            . join(', ',
                 map {
                    "$_="
                    . (defined $vals_too_high{$_} ? $vals_too_high{$_}
                                                  : 'unknown')
                 } sort keys %vals_too_high
              )
            . ".\n";
         return;
      };
      $pr->set_callback($pr_callback);
   }

   # Wait until all vars' vals are < their permitted maximums.
   while ( $oktorun->() ) {
      PTDEBUG && _d('Checking status variables');
      foreach my $var ( sort keys %vals_too_high ) {
         my $val = $get_status->($var);
         PTDEBUG && _d($var, '=', $val);
         if ( !$val || $val >= $self->{max_val_for}->{$var} ) {
            $vals_too_high{$var} = $val;
         }
         else {
            delete $vals_too_high{$var};
         }
      }

      last unless scalar keys %vals_too_high;

      PTDEBUG && _d(scalar keys %vals_too_high, 'values are too high:',
         %vals_too_high);
      if ( $pr ) {
         # There's no real progress because we can't estimate how long
         # it will take the values to abate.
         $pr->update(sub { return 0; });
      }
      PTDEBUG && _d('Calling sleep callback');
      $sleep->();
      %vals_too_high = %{$self->{max_val_for}}; # recheck all vars
   }

   PTDEBUG && _d('All var vals are low enough');
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End MySQLStatusWaiter package
# ###########################################################################