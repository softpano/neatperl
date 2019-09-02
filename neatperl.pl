#!/usr/bin/perl
#:: neatperl version 1.1 (July 14, 2012)
#:: KISS-style pretty printer for PErl scripts
#:: Nikolai Bezroukov, 2010.  Perl Artistic license
#::
#:: The key idea is to use only last and first symbols for  determining the nesting level
#::that requres a certain layout of Perl script for reformatiing to be sucessful.
#::can't be used with arbitrary scripts without modification of the source.
#::
#:: --- INVOCATION
#::
#::   neatperl [options] [file_to_process]
#::
#::--- OPTIONS
#::
#::    -v -- display version
#::    -h -- this help
#::    -t number -- size of tab (emulated with spaces)
#::    -b--  number of the line to switch to into debugging mode
#::    -w --  provide warning about non-banace of quotes and round patenthesdefault warning threshold (default 50)
#::
#::
#::  Parameters
#::    1st -- name of  file
#::
#--- Development History
#
# Ver      Date        Who        Modification
# ====  ==========  ========  ==============================================================
# 1.00  2012/07/12  BEZROUN   Initial implementation
# 1.10  2012/07/14  BEZROUN    Parameter processing added
# 2.10  2019/08/30  BEZROUN    logic improvebased on experince with neatbash
#=========================== START =========================================================
use Getopt::Std;
use warnings;

   $major_version=1; $minor_version='00';
   $main::SCRIPT_NAME=substr($0,0,rindex($0,'.'));
   $OS=$^O; # $^O is built-in Perl variable that contains OS name
   banner("$main::SCRIPT_NAME version $major_version.$minor_version\n");
   $debug=0;
   $breakpoint=-1;
   $tab=3;
   $mode='f';
   get_params();

   $new_nest=$cur_nest=0;

  while($line=<STDIN>) {
    $inbalance='';
    $intact_line=$line;
    chomp($line);
    $lineno++;
    if ($lineno == $breakpoint) {
       $DB::single = 1
    }
    #
    # check for comment lines
    #
    if (substr($line,0,1) eq '#') {
      listing($line);
      next;
    }

   # trim blanks
   if ($line=~/^\s*(\S.*\S)\s*$/  || $line=~/^\s*(\S)\s*$/) {
      $line=$1;
   }

   if ( length($line)==0) {
      listing($line);
      next;
   }

   $first_sym=substr($line,0,1);
   if ( $first_sym eq '#') {
      listing($line);
      next;
    }
   if ($first_sym eq '{') {
      $new_nest++;
   } elsif ($first_sym eq '}') {
      $new_nest--;
      $cur_nest=$new_nest;
   }

   if (length($line) == 1) {
      $cur_nest=$new_nest;
      listing($line);
      next;
   }

   # Step 2: check the last symbol for "{" Note: comments are prohibited on such lines
   $last_sym=substr($line,-1,1);
   if ($last_sym eq '{') {
      $new_nest++;
   } elsif ($last_sym eq '}') {
      ($debug) && print "--- $line\n";
       # if there is ; on the line ending with } we assume that line does not change nesting level
       unless ($line =~/\;\s*}$/) {
          $new_nest--;
       }
   } # if
   scan_line($line);
   listing($line);
   $cur_nest=$new_nest;
 } # while

sub scan_line
{
my $i;
my $scan_text=$_[0];

   if ($first_sym =~/[{}]/) {
      $scan_text=substr($scan_text,1);
   }
   if ($last_sym =~/[{}]/) {
      $scan_text=substr($scan_text,0,-1)
   }
   $sq_br=0;
   $round_br=0;
   $curve_br=0;
   $single_quote=0;
   $double_quote=0;
   for ($i=0; $i<length($scan_text); $i++) {
     $s=substr($scan_text,$i,1);
     if ($s eq '{') { $curve_br++;} elsif ($s eq '}') { $curve_br--; }
     if ($s eq '(') { $round_br++;} elsif ($s eq ')') { $round_br--; }
     if ($s eq '[') { $sq_br++;} elsif ($s eq ']') { $sq_br--; }

     if ( $s eq "'" ) { $single_quote++;}
     if ( $s eq '"' ) { $double_quote++;}

   }
   if ( $single_quote%2==1 ) { $inbalance.="'";}
   elsif ( $double_quote%2==1 ) {  $inbalance.='"'; }
   if ($single_quote%2==0 && $double_quote%2==0) {
      if ( $curve_br>0) {
        $inbalance ='{';
      } elsif ( $curve_br<0 ) {
         $inbalance ='}';
      }

      if ( $round_br>0 ) {
        $inbalance ='(';
      } elsif ( $round_br<0 ) {
        $inbalance =')';
      }
      if ( $sq_br>0 ) {
        $inbalance ='[';
      } elsif ( $sq_br<0 ) {
        $inbalance =']';
      }
   }

}
sub listing#
###================================================= NAMESPACE sp: My SP toolkit subroutines
#

sub prolog
{
my $SCRIPT_NAME=$_[0];
my $SCRIPT_DIR=$_[1];
#
# Set message  prefix
#
   $message_prefix=$main::SCRIPT_NAME;
   if( substr($message_prefix,0,2) eq 'sp' ){
       $message_prefix=substr($message_prefix,2);
   }
   $message_prefix=~tr/aeioyu[0-9]//d;
   $message_prefix=substr(uc($message_prefix),0,4);
#
# Locate key utilities via which and store them in variables. It allow you to disable action of any selected ustility by  ubstituting it to echo
#
  #$LS='/bin/ls';
  #$MAIL='/bin/mail';
  #$CAT='/bin/cat';
  $FIND=`which find`; chomp $FIND;
  $MV=`which mv`; chomp $MV;
  $CP=`which cp`; chomp $CP;
  $DIFF=`which diff`; chomp $DIFF;
  #$LAST='/usr/bin/last';
  $DATE=`which date`; chomp $DATE;
  $MKDIR=`which mkdir`; chomp $MKDIR;
  #$GREP='/bin/grep';
#
# Commit each running version to the repository
#
my $SCRIPT_TIMESTAMP;
my $script_delta=1;
  if ( -f "$SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl" ) {
     if( (-s "$SCRIPT_DIR/$main::SCRIPT_NAME.pl") == (-s "$SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl")   ){
        `diff $SCRIPT_DIR/$main::SCRIPT_NAME.pl $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl`;
        if ( $? == 0 ) {
           $script_delta=0;
        }
     }
     if( $script_delta > 0 ){
        chomp($SCRIPT_TIMESTAMP=`date -r $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl +"%y%m%d_%H%M"`);
       `mv $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.$SCRIPT_TIMESTAMP.pl`;
       `cp -p $SCRIPT_DIR/$main::SCRIPT_NAME.pl $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl `;
     }
   } else {
      `cp -p $SCRIPT_DIR/$main::SCRIPT_NAME.pl $SCRIPT_DIR/Archive/$main::SCRIPT_NAME.pl `;
   }

} # prolog


# Read script and extract help from comments starting with #::
#
sub helpme
{
   open(SYSHELP,"<$0");
   while($line=<SYSHELP> ){
      if(  substr($line,0,3) eq "#::" ){
         print substr($line,3);
      }
   } # for
   close SYSHELP;
   exit;
}

#
# Teminate program (variant without mailing)
#
sub abend
{
my $message;
my $lineno=$_[0];
   if (scalar(@_)==1) {
      $message="ABEND at $lineno. No message was provided for abend call. Exiting.";
   }else{
      $message="$lineno $_[1]. Exiting ";
   }
#  Syslog might not be availble
   out($message);
   die("Abend at $lineno. $message");
} # abend
#
# Inital banner
# dependw of two variable from main namespace: VERSION and debug
sub banner {
#
# Sanity check
#
   if (scalar(@_)<2) {
      die("Incorrect call to banner; less then three argumnets passed".join("\n",@_));
   }
#
# Decode obligatory arguments
#
my $LOG_DIR=$_[0];
my $SCRIPT_NAME=$_[1];
my $LOG_RETENTION_PERIOD=$_[2];
#
# optional arguments
#
my $subtitle;
if (scalar(@_)>2) {
   $subtitle=$_[3]; # this is an optional argumnet which is printed as subtitle after the title.
}

my $timestamp=`date "+%y/%m/%d %H:%M"`;
   chomp $timestamp;

my $SCRIPT_MOD_DATE=`date -r /cygdrive/f/_Scripts/$main::SCRIPT_NAME.pl +"%y%m%d_%H%M"`;
   chomp $SCRIPT_MOD_DATE;

my $title="\n\n".uc($main::SCRIPT_NAME).": Cleaner for html ChunksA. Version $main::VERSION ($SCRIPT_MOD_DATE) DEBUG=$main::debug Date $timestamp";
my $day=`date '+%d'`; chomp $day;

   if( 1 == $day && $LOG_RETENTION_PERIOD>0 ){
     #Note: in debugging script home dir is your home dir and the last thing you want is to clean it ;-)
      `$FIND $LOG_DIR -name "*.log" -type f -mtime +$LOG_RETENTION_PERIOD -delete`; # monthly cleanup
   }
my $logstamp=`date +"%y%m%d_%H%M"`; chomp $logstamp;
   $LOG_FILE="$LOG_DIR/$main::SCRIPT_NAME.$logstamp.log";
   unless ( -e $LOG_DIR ){
      `$MKDIR -p $LOG_DIR`;
   }
   open(SYSLOG, ">$LOG_FILE") || abend(__LINE__,"Fatal error: unable to open $LOG_FILE");

   out($title); # output the banner

   unless ($subtitle ){
      $subtitle="Logs are at $LOG_FILE. Type -h for help.\n";
   }
   out("$subtitle");
   out ("================================================================================\n\n");

}


# ================================================================================ LOGGING ===========================================================

#
# Message generator: Record message in log and STDIN
# PARAMETERS:
#            lineno, severity, message
# ARG1 lineno, If it is negative skip this number of lines
# Arg2 Error code (the first letter is severity, the second letter can be used -- T is timestamp -- put timestamp inthe message)
# Arg3 Text of the message
# NOTE: $top_severity, $verbosity1, $verbosity1 are state variables that are initialized via special call to sp:: sp::logmes

sub logme
{
#our $top_severity; -- should be defined globally

my $lineno=$_[0];
my $message=$_[2];
   chomp($message); # we will add \n ourselves

state $verbosity1; # $verbosity console
state $verbosity2; # $verbosity for log
state $msg_cutlevel1; # variable 6-$verbosity1
state $msg_cutlevel2; # variable 5-$verbosity2
state @ermessage_db; # accumulates messages for each caterory (warning, errors and severe errors)
state @ercounter;
state $delim='=' x 80;
state $linelen=110; # max allowed line length


#
# special cases -- "negative lineno": -1 means set msglevel1 and msglevel2, 0 means print in log and console -- essentially out($message)
#

if( $lineno<=0 ){
   if( $lineno == -1 ){
        $verbosity1=$_[1];
        $verbosity2=$_[2];
        $msg_cutlevel1=length("DIWEST")-$verbosity1-1;
        $msg_cutlevel2=length("DIWEST")-$verbosity2-1;

    }elsif( 00==$lineno ){
         # this is eqivalenet of out: put obligatory message on console and into log)
         out($message);
    }
   return;
} #if
#
# Now let's process "normal message, which should have severty code.
#
my $error_code=substr($_[1],0,1);
my $error_suffix=(length($_[0])>1) ? substr($_[1],1,1):'';


my $severity=index("diwest",lc($error_code));
#
# Increase messages counter  for given severity (supressed messages are counted too)
#
      if( $severity> -1 ){ $ercounter[$severity]++;}
#
# Stop processing if the message is too trivial for current msglevel1 and msglevel2
#
      return if(  $severity<$msg_cutlevel1 && $severity<$msg_cutlevel2 ); # no need to process if this is lower then both msglevels
#
# From diagnostic message from error code, line number and message (optionally timestamp is suffic of error code is T)
#
$message="$message_prefix\-$lineno$error_code: $message";
   if ($severity eq 'I') {
      out($message);
      return;
   }

#----------------- Error history -------------------------
      if(  $severity > 2 ){
         # Errors and above should be stored so that later then can be displayed in summary.
         $ermessage_db[$severity] .= "\n\n$message";
      }
#--------- Message printing and logging --------------
      if( $severity<5  ){
            if( $severity >= $msg_cutlevel2 ){
               # $msg_cutlevel2 defines writing to SYSLOG. 3 means Errors (Severe and terminal messages always whould be printed)
               if( $severity<4 ){
                  print SYSLOG "$message\n";
               } else {
                  # special treatment of serious messages
                  print SYSLOG "$delim\n$message\n$delim\n";
               }
            }
            if( $severity >= $msg_cutlevel1 ){
               # $msg_cutlevel1 defines writing to STDIN. 3 means Errors (Severe and terminal messages always whould be printed)
               if( $severity<3 ){
                   if( length($message) <$linelen ){
                      print "$message\n";
                   } else {
                      $split_point=rindex($message,' ',$linelen);
                      if( $split_point>0 ){
                         print substr($message,0, $split_point);
                         print "\n   ".substr($message, $split_point)."\n";
                      } else {
                         print substr($message,0,$linelen);
                         print "\n   ".substr($message,$linelen)."\n";
                      }
                   }
               } else {
                  print "$delim\n$message\n$delim\n";
               }
            }
            return;
      } # $severity<5
#
# code 'T' now means "issue summary and terminate, if message contains the word ABEND" (using state variables now defined within sp:: sp::logme) -- Nov 12, 2015
#

my $summary;
my $counter;
my $delta_chunks;
   #
   # We will put the most severe errors at the end and make 15 sec pause before  read them
   #

   for( $counter=1; $counter<=length('DIWEST'); $counter++ ){
      next unless( $ercounter[$counter] );
      $summary.=" ".substr('DIWEST',$counter,1).": ".$ercounter[$counter];
   } # for
   out("\n\n=== MESSAGES SUMMARY $summary\n");
   out($_[2]);
   if( $ercounter[2] + $ercounter[3] + $ercounter[4] ){
      # print errors & severe errors
      for(  $severity=1;  $severity<5; $severity++ ){
          # $ermessage_db[$severity]
          if( $ercounter[$severity]>0 ){
             out("$ermessage_db[$severity]\n\n");
          }
      }
   }
#
# Final messages
#
  out("\n*** PLEASE CHECK $ercounter[4] SERIOUS MESSAGES ABOVE");
  out($_[2]);
  if( index($message,'ABEND') ){
    exit; # messages with the word ABEND (in capital) terminate the program
  }
} # logme
#
# Output message to syslog and print
#
sub out
{
   if (scalar(@_)==0) {
      print;
      print SYSLOG;
      return;
   }
   print "$_[0]\n";
   print SYSLOG "$_[0]\n";
}
sub shell {
   if( $main::debug ){ sp::logme(__LINE__,'I',"command: $_[0]");}
   `$_[0]`;
}
sub step
{
   $DB::single = 1;
}
{

   $prefix=sprintf('%4u %3d %5s',$lineno, $cur_nest, $inbalance);
   if ($cur_nest<0 || substr($intact_line,0,1) =~ /\S/) {
      $spaces='';
   } else {
      $spaces= ' ' x (($cur_nest+1)*$tab);
   }
   print "$prefix | $spaces$_[0]\n";
   if ($mode eq 'f') {
      print SYSFORM "$spaces$_[0]\n";
   }

}
sub get_params
{
#
# process parameters and options
#
   getopts("t:fvh",\%options);
   if ( exists $options{'v'}) {
      banner();
      print "Options -h, -v, -c file\n";
      exit;
   } elsif ( exists $options{'h'}) {
      helpme();
   } elsif ( exists $options{'f'} ) {
       $mode='f';
   } elsif ( exists $options{'t'} ) {
      if ($options{'t'}>0  && $options{'t'}<10) {
         $tab=$options{'t'};
      } else {
        die("Wrong value of option -t (tab size): $options('t')\n");
      }
   } elsif ( exists $options{'b'} ) {
      if ($options{'b'}>0  && $options{'t'}<1000) {
         $breakpoint=$options{'b'};
      } else {
        die("Wrong value of option -b (line for debugger breakpoint): $options('b')\n");
      }
   }

   if ($mode eq 'f') {
       if (scalar(@ARGV)==0) {
          die ("Name of the file to reformat is not supplied\n");
       }
       $fname=@ARGV[0];
       #create backup file
       $source_file="$fname.bak";
       rename($fname,$source_file);
    } else {
       $source_file=$ARGV[0];
    }
    if (scalar(@ARGV)==0) {
       open (STDIN, ">-");
    } elsif (scalar(@ARGV)==1) {
       open (STDIN, "<$source_file");
    } else {
       $args=join(' ', @ARGV);
       die ("Too many arguments: $args")
    }
    open (SYSOUT, ">-" );
    if ($mode eq "f") {
       open (SYSFORM,">$fname");
    }

}

