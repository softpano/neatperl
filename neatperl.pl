#!/usr/bin/perl
#:: neatperl version 1.2 (August 30, 2019)
#:: Fuzzy prettyprint STDERRer for Perl scripts
#:: Nikolai Bezroukov, 2019.
#:: Licensed under Perl Artistic license
#::
#:: The key idea if fuzzy reformating is use only last and first symbols of the line for  determining the nesting level.
#:: in most cases this is sucessful approach and in a few case when it is not it is easovy corrected using pragma %set_nest_level
#:: That's why we use the term "fuzzy".
#:: To be sucessful, this approach requres a certain (very resonable) layout of the script.
#:: But there some notable exceptions. For example, for script compless to eliminate whitespece this approach  is not sucessful
#::
#:: --- INVOCATION:
#::
#::   neatperl [options] [file_to_process]
#::
#::--- OPTIONS:
#::
#::    -v -- display version
#::    -h -- this help
#::    -t number -- size of tab (emulated with spaces)
#::    -f  -- writen formattied test into the same files creating backup
#::    -w --  provide additonal warnings about non-balance of quotes and round patenthes
#::
#::--- PARAMETERS:
#::    1st -- name of  file
#::
#::    NOTE: With option -p the progrem can be used as a stage fo the pipe. FOr example#::
#::       cat my_script.sh | neatperl -p > my_script_formatted.sh
#--- Development History
#
# Ver      Date        Who        Modification
# ====  ==========  ========  ==============================================================
# 0.10  2012/07/12  BEZROUN   Initial implementation
# 0.20  2012/07/14  BEZROUN    Parameter processing added
# 0.30  2019/08/30  BEZROUN    logic improved based on experience with writing neatperl
# 0.40  2019/08/31  BEZROUN    Formatter listing redirected to STDERR. The ability to work as a pipe
# 0.50  2019/09/03  BEZROUN    Checking of re-formatted script via  perl -cw
# 0.60  2019/09/14  BEZROUN    Readability option (-r) implemented
# 0.61  2019/09/17  BEZROUN    Minor changes and cleanup of logging infrastructure.
# 0.70  2019/09/19  BEZROUN    Keyword sub in first position iv viewed as the subrotime and checked for nesting level 0.
# 0.70  2019/09/19  BEZROUN    Directive #%NEST=0 produces error message if calculated NEST not equal to zero.
# 0.71  2019/10/04  BEZROUN    Severity handing in logme improved: if code does not exist just print the message.
# 0.71  2019/10/04  BEZROUN    Prolog made more plexible by specifing bothe home and archive directories.
#=========================== START =========================================================
#=== Start
   use v5.10;
#  use Modern::Perl;
   use warnings;
   use strict 'subs';
   use feature 'state';
   use Getopt::Std;

   $VERSION='0.71';
   $debug=1; # 0 production mode 1 - development/testing mode. 2-9 debugging modes
   #$debug=1;  # enable saving each source version without compile errors to GIT
   better diagnistics, but the result is written to the disk
   #$debug=2; # starting from debug=2 the results are not written to disk
   #$debug=3; # starting from Debug=3 only the first chunk processed

# INTERESTING, VERY NEAT IDEA: you can switch on tracing from particular line of source ( -1 to disable)
   $breakpoint=-1;
   $SCRIPT_NAME=substr($0,rindex($0,'/')+1);
   if( ($dotpos=index($SCRIPT_NAME,'.'))>-1 ) {
      $SCRIPT_NAME=substr($SCRIPT_NAME,0,$dotpos);
   }
   $git_repo='';
   $OS=$^O; # $^O is built-in Perl variable that contains OS name
   if($OS eq 'cygwin' ){
      $HOME="/cygdrive/f/_Scripts";  # $HOME/Archive is used for backups
   }elsif($OS eq 'linux' ){
      $HOME=ENV{'HOME'}; # $HOME/Archive is used for backups
   }
   $LOG_DIR="/tmp/$SCRIPT_NAME";


   $tab=3;
   $write_formatted=0; # flag that dremines if we need to write the result into the file supplied.
   $write_pipe=0;
   $readability_plus=0;
   %keyword=('if'=>1,'while'=>1,'unless'=>1, 'until'=>1,'for'=>1,'foreach'=>1,'given'=>1,'when'=>1,'default'=>1);

   if( $debug>0 ){
      logme('D',2,2); # Max verbosity
   } else {
      logme('D',1,2); # E and S to console, everything to the log.
   }
   banner($LOG_DIR,$SCRIPT_NAME,'Simple Perl prettyprinter',30); # Opens SYSLOG and print STDERRs banner; parameter 4 is log retention period
   get_params();
   prolog("$HOME/Archive",$git_repo);

   if( $debug==0 ){
      print STDERR "$SCRIPT_NAME (version $VERSION) is working in production mode\n";
   } else {
      print STDERR "ATTENTION!!! $SCRIPT_NAME (version $VERSION) is working in debugging mode debug=$debug\n";
   }
   print STDERR 80 x "=","\n\n";

#
# Main loop initialization variables
#
   $new_nest=$cur_nest=0;
   #$top=0; $stack[$top]='';
   $lineno=0;
   $fline=0; # line number in formatted code
   $here_delim="\n"; # impossible combination
   $noformat=0;
   $InfoTags='';
#
# MAIN LOOP
#
   while($line=<STDIN> ){
      $offset=0;
      chomp($line);
      $intact_line=$line;
      $lineno++;
      if( $lineno == $breakpoint ){
         $DB::single = 1
      }
      if( substr($line,-1,1) eq "\r" ){
         chop($line);
      }
      # trip traling blanks, if any
      if( $line=~/(^.*\S)\s+$/ ){
         $line=$1;
      }

      #
      # Check for HERE line
      #

      if($noformat){
         if( $line eq $here_delim ){
            $noformat=0;
            $InfoTags='';
         }
         process_line(-1000);
         next;
      }

      if( $line =~/<<['"](\w+)['"]$/ ){
         $here_delim=$1;
         $noformat=1;
         $InfoTags='HERE';
      }
      #
      # check for comment lines
      #
      if( substr($line,0,1) eq '#' ){
         if( $line eq '#%OFF' ){
            $noformat=1;
            $here_delim='#%ON';
            $InfoTags='OFF';
         }elsif( $line =~ /^#%ON/ ){
            $noformat=0;
         }elsif( substr($line,0,6) eq '#%NEST') {
            if( $line =~ /^#%NEST=(\d+)/) {
               if( $cur_nest != $1 ) {
                  $cur_nest=$new_nest=$1; # correct current nesting level
                  $InfoTags="=$cur_nest";
               }else{
                  $InfoTags="OK $cur_nest";
               }
            }elsif( $line =~ /^#%NEST++/) {
               $cur_nest=$new_nest=$1+1; # correct current nesting level
               $InfoTags='+1';
            }elsif( $line =~ /^#%NEST--/) {
               $cur_nest=$new_nest=$1+1; # correct current nesting level
               $InfoTags='-1';
            }elsif( $line =~ /^#%ZERO\?/) {
               if( $cur_nest == 0 ) {
                  $InfoTags="OK $cur_nest";
               }else{
                  $InfoTags="??";
                  logme('E',"Nest is $cur_nest instead of zero");
                  $cur_nest=0;
               }
            }
         }
         process_line(-1000);
         next;
      }
      if ( $line =~ /^sub\s+\w+/ && $cur_nest != 0 ) {
         if ($cur_nest>0) {
            $InfoTags='} ?';
         }else{
            $InfoTags='{ ?';
         }
      }
      if( $line eq '__END__' || $line eq '__DATA__' ) {
         $noformat=1;
         $here_delim='"'; # No valid here delimiter in this case !
         $InfoTags='DATA';
      }
      if( substr($line,0,1) eq '=' && $line ne '=cut' ){
         $noformat=1;
         $InfoTags='POD';
         $here_delim='=cut'
      }

      # blank lines should not be processed
      if( $line =~/^\s*$/ ){
         process_line(-1000);
         next;
      }
      # trim leading blanks
      if( $line=~/^\s*(\S.*$)/){
         $line=$1;
      }
      # comments on the level of nesting 0 should start with the first position
      if( substr($line,0,1) eq '#' ){
         process_line(0);
         next;
      }

      # comments on the level of nesting 0 should start with the first position
      $first_sym=substr($line,0,1);
      if( substr($line,0,1) eq '#' ){
         process_line(0);
         next;
      }
      if( $first_sym eq '{' ){
         $new_nest++;
      } elsif( $first_sym eq '}' ){
         $new_nest--;
         $offset=-1;

      }
      # Step 2: check the last symbol for "{" Note: comments are prohibited on such lines
      $last_sym=substr($line,-1,1);
      if( $last_sym eq '{' && length($line)>1 ){
         $new_nest++;
      }# if
      #elsif( $last_sym eq '}' && length($line)==1  ){
      # NOTE: only standalone } on the line affects effective nesting; line that has other symbols is assumed to be like if (...) { )
      # $new_nest-- is not nessary as as it is also the first symbol and nesting was already corrected
      #}
      unless( substr($intact_line,0,1) =~/\s/){
         $offset=-1000;
      }
      process_line($offset);

   } # while
#
# Epilog
#

   if( $cur_nest !=0 ){
      logme('E',"Final nesting is $cur_nest instead of zero");
      ( $write_formatted >0 || $write_pipe > 0  ) && logme('E',"Writing formatted code is blocked");
      exit 16;
   }
   if( $write_formatted >0 || $write_pipe > 0  ){
      write_formatted_code();
   }
   exit 0;

#
# Subroutines
#
sub process_line
{
      my $offset=$_[0];

      if( length($line)>1 && substr($line,0,1) ne '#' ){
         check_delimiter_balance($line);
      }
      $prefix=sprintf('%4u %3d %4s',$lineno, $cur_nest, $InfoTags);
      if( substr($intact_line,0,1) =~ /\S/ ){
         $spaces='';
      }elsif( ($cur_nest+$offset)<0 || $cur_nest<0 ){
         $spaces='';
      }else{
         $spaces= ' ' x (($cur_nest+$offset+1)*$tab);
      }
      if( $readability_plus==1 ){
         # should affect only line starting with defined keywords
         if( $line=~/^(\w+)/ ){
            $first_word=$1;
            if( exists($keyword{$first_word}) ){
               substr($line,0,length($first_word))='';
               if( $line=~/^(\s+\(\s*)/ ){
                  substr($line,0,length($1))=''; # remove ( with surrounding white spaces
                  $line=$first_word.'( '.$line; #restore the line
                  if( substr($line,-3,3) eq ') {' ){
                     substr($line,-3,3)=' ){';
                  }
               }else {
                  $line=$first_word.$line;
               }
            }
         }
      }
      print STDERR "$prefix | $spaces$line\n";
      if( $write_formatted > 0 ){
         $formatted[$fline++]="$spaces$line\n";
      }
      $cur_nest=$new_nest;
      if( $noformat==0 ){ $InfoTags='' }
}
sub  write_formatted_code
{
      if( -f $fname ){
         chomp($timestamp=`date +"%y%m%d_%H%M"`);
         $fname_backup=$fname.'.'.$timestamp;
         `cp -p $fname $fname_backup`;
         if( $? > 0  ){
            abend("Unable to create a backup");
         }
      }
      if( $write_formatted ){
         open (SYSFORM,'>',"$fname.neat") || abend(__LINE__,"Cannot open file $fname.neat for writing");
         print SYSFORM @formatted;
         close SYSFORM;
         `perl -cw $fname.neat`;
         if(  $? > 0 ){
            logme('E',"Checking reformatted code via perl -cw produced some errors (RC=$?). The original file left intact. Reformatted file is $fname.neat");
         } else {
            close STDIN;
            `mv $fname.neat $fname`;
         }
      }elsif( $write_pipe ){
         print @formatted;
      }
}
#
# Check delimiters balance without lexical parcing of the string
#
sub check_delimiter_balance
{
my $i;
my $scan_text=$_[0];
      $sq_br=0;
      $round_br=0;
      $curve_br=0;
      $single_quote=0;
      $double_quote=0;
      return if( length($_[0])==1 || $line=~/.\s*#/); # no balance in one symbol line.
      for( $i=0; $i<length($scan_text); $i++ ){
         $s=substr($scan_text,$i,1);
         if( $s eq '{' ){ $curve_br++;} elsif( $s eq '}' ){ $curve_br--; }
         if( $s eq '(' ){ $round_br++;} elsif( $s eq ')' ){ $round_br--; }
         if( $s eq '[' ){ $sq_br++;} elsif( $s eq ']' ){ $sq_br--; }

         if(  $s eq "'"  ){ $single_quote++;}
         if(  $s eq '"'  ){ $double_quote++;}
      }
      if(  $single_quote%2==1  ){ $InfoTags.="'";}
      elsif(  $double_quote%2==1  ){  $InfoTags.='"'; }

      $first_word=( $line=~/(\w+)/ ) ? $1 : '';

      if( $single_quote%2==0 && $double_quote%2==0 ){
         unless( exists($keyword{$first_word}) ){
            if( $curve_br>0 && index($line,'\{') == -1 ){
               $inbalance ='{';
               ( $single_quote==0 && $double_quote==0 ) && logme('W',"Possible missing '}' on the following line:");
            } elsif(  $curve_br<0  ){
               $inbalance ='}';
               ( $single_quote==0 && $double_quote==0 ) && logme('W',"Possible missing '{' on the following line:  ");
            }
         }

         if(  $round_br>0 && index($line,'\(') == -1 ){
            $inbalance ='(';
            ( $single_quote==0 && $double_quote==0 ) && logme('W',"Possible missing ')' on the following line:");
         }elsif(  $round_br<0  ){
            $inbalance =')';
            ( $single_quote==0 && $double_quote==0 ) && logme('W',"Possible missing '(' on the following line:");
         }

         if(  $sq_br>0 && index($line,'\[') == -1  ){
            $inbalance ='[';
            ( $single_quote==0 && $double_quote==0 ) &&logme('W',"Possible missing ']' on the following line:");
         } elsif(  $sq_br<0  ){
            $inbalance =']';
            ( $single_quote==0 && $double_quote==0 ) && logme('W',"Possible missing '[' on the following line:");
         }
      }

}
#
# process parameters and options
#
sub get_params
{
      getopts("fhrb:t:v:d:",\%options);
      if(  exists $options{'v'} ){
         if( $options{'v'} =~/\d/ && $options{'v'}<3  ){
            logme('D',$options{'v'},);
         }else{
            logme('D',3,3); # add warnings
         }
      }
      if(  exists $options{'h'} ){
         helpme();
      }
      if(  exists $options{'p'}  ){
         $write_formatted=0;
         $write_pipe=1;
      }

      if(  exists $options{'f'}  ){
         $write_formatted=1;
      }
      if(  exists $options{'r'}  ){
         $readability_plus=1;
      }
      if(  exists $options{'t'}  ){
         if( $options{'t'}>0  && $options{'t'}<10 ){
            $tab=$options{'t'};
         } else {
            die("Wrong value of option -t (tab size): $options('t')\n");
         }
      }

      if(  exists $options{'b'}  ){
         if( $options{'b'}>0  && $options{'t'}<1000 ){
            $breakpoint=$options{'b'};
         } else {
            die("Wrong value of option -b (line for debugger breakpoint): $options('b')\n");
         }
      }

      if(  exists $options{'d'}  ){
         if( $debug =~/\d/ ){
            $debug=$options{'d'};
         }elsif( $options{'d'} eq '' ){
            $debug=1;
         }else{
            die("Wrong value of option -d: $options('d')\n");
         }
      }

      if( scalar(@ARGV)==0 ){
         open (STDIN, ">-");
         $write_formatted=0;
         return;
      }

      if( scalar(@ARGV)==1 ){
         $fname=$ARGV[0];
         unless( -f $fname ){
            die ("Unable to open file $ARGV[0]");
         }
         open (STDIN, "<$fname");
      } else {
         $args=join(' ', @ARGV);
         die ("Too many arguments: $args")
      }

}
#
###================================================= NAMESPACE sp: My SP toolkit subroutines
#
#
# Create backup and commit script to GIT repository if there were changes from previous version.
#
#package sp;
sub prolog
{

my $archive_dir=$_[0]; # typically home or $HOME/bin
my $git_repo=$_[1]; # typically home or $HOME/bin
#
# Set script name and  messages prefix
#
my $script_name=substr($0,rindex($0,'/')+1);
    $MessagePrefix=substr($script_name,0,4);
#
# End of global initialization
#
    return if($debug == 0);
#
# As debug>0 commit each running version to the repository to central GIT
#

my $script_timestamp;
my $script_delta=1;
my $host=`hostname -s`;
      chomp($host);
      if(  -f "$archive_dir/$script_name"  ){
         if( (-s $0 ) == (-s "$archive_dir/$script_name")   ){
            `diff $0 $archive_dir/$script_name`;
            $script_delta=( $? == 0 )? 0: 1;
         }

         if( $script_delta ){
            chomp($script_timestamp=`date -r $archive_dir/$script_name +"%y%m%d_%H%M"`);
            `mv $archive_dir/$script_name $archive_dir/$script_name.$script_timestamp`;

         }
      }
      ($script_delta) && `cp -p $0 $archive_dir/$script_name`;
      ($git_repo) && `cd $archive_dir && git commit $git_repo`;
} # prolog

# Read script and extract help from comments starting with #::
#
sub helpme
{
      open(SYSHELP,"<$0");
      while($line=<SYSHELP> ){
         if(  substr($line,0,3) eq "#::" ){
            print STDERR substr($line,3);
         }
      } # for
      close SYSHELP;
      exit;
}

#
# Terminate program (variant without mailing)
#
sub abend
{
my $message;
my $lineno=$_[0];
      if( scalar(@_)==1 ){
         $message=$MessagePrefix.$lineno."T  ABEND at $lineno. No message was provided. Exiting.";
      }else{
         $message=$MessagePrefix.$lineno."T $_[1]. Exiting ";
      }
#  Syslog might not be availble
      out($message);
      die("Abend at $lineno. $message");
} # abend

#
# Open log and output the banner; if additional arguments given treat them as subtitles
#        depends of two variable from main namespace: VERSION and debug
sub banner {
#
# Sanity check
#
      if( scalar(@_)<4 ){
         die("Incorrect call to banner; less then four arguments passed".join("\n",@_));
      }
#
# Decode obligatory arguments
#
my $my_log_dir=$_[0];
my $script_name=$_[1];
my $title=$_[2]; # this is an optional argumnet which is print STDERRed as subtitle after the title.
my $log_retention_period=$_[3];

my $timestamp=`date "+%y/%m/%d %H:%M"`; chomp $timestamp;
my $day=`date '+%d'`; chomp $day;
my $logstamp=`date +"%y%m%d_%H%M"`; chomp $logstamp;
my $script_mod_stamp;
      chomp($script_mod_stamp=`date -r $0 +"%y%m%d_%H%M"`);
      if( -d $my_log_dir ){
         if( 1 == $day && $log_retention_period>0 ){
            #Note: in debugging script home dir is your home dir and the last thing you want is to clean it ;-)
            `find $my_log_dir -name "*.log" -type f -mtime +$log_retention_period -delete`; # monthly cleanup
         }
      }else{
         `mkdir -p $my_log_dir`;
      }

my $logfile="$my_log_dir/$script_name.$logstamp.log";
      open(SYSLOG, ">$logfile") || abend(__LINE__,"Fatal error: unable to open $logfile");
      $title="\n\n".uc($script_name).": $title (last modified $script_mod_stamp) Running at $timestamp\nLogs are at $logfile. Type -h for help.\n";
      out($title); # output the banner
      for( my $i=4; $i<@_; $i++) {
         out($_[$i]); # optional subtitles
      }
      out ("================================================================================\n\n");
} #banner

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
my $error_code=substr($_[0],0,1);
my $error_suffix=(length($_[0])>1) ? substr($_[0],1,1):''; # suffix T means add timestamp
my $message=$_[1];
      chomp($message); # we will add \n ourselves

state $verbosity1; # $verbosity console
state $verbosity2; # $verbosity for log
state $msg_cutlevel1; # variable 6-$verbosity1
state $msg_cutlevel2; # variable 5-$verbosity2
state @ermessage_db; # accumulates messages for each caterory (warning, errors and severe errors)
state @ercounter;
state $delim='=' x 80;

#
# special cases -- ercode "D" means set msglevel1 and msglevel2, ' ' means print STDERR in log and console -- essentially out with messsage header
#

      if( $error_code eq 'D' ){
         # You can dynamically change verbosity within the script by issue D message.
         $verbosity1=$_[1];
         $verbosity2=$_[2];
         $msg_cutlevel1=length("WEST")-$verbosity1-1; # verbosity 3 is max and means 4-3-1 =0 is index correcponfing to  ('W')
         $msg_cutlevel2=length("WEST")-$verbosity2-1; # same for log only (like in MSGLEVEL mainframes ;-)
         return;
      }
      unless ( $error_code ){
         # Blank error code is equivalent of out: put obligatory message on console and into log
         out($message);
         return;
      }

      my ($package, $filename, $lineno) = caller;
#
# Now let's process "normal message, which should have severty code.
#

#
# Increase messages counter  for given severity (supressed messages are counted too)
#
#
# Generate diagnostic message from error code, line number and message (optionally timestamp is suffix of error code is T)
#
      $message="$MessagePrefix\-$lineno$error_code: $message";
      my $severity=index("west",lc($error_code));
      if( $severity == -1 ){
         out($message);
         return;
      }

      $ercounter[$severity]++;
      $ermessage_db[$severity] .= "\n\n$message"; #Error history for the ercodes E and S
      return if(  $severity<$msg_cutlevel1 && $severity<$msg_cutlevel2 ); # no need to process if this is lower then both msglevels

      if( $severity < 3 ){
#
# Stop processing if severity is less then current msglevel1 and msglevel2
#
         if( $severity >= $msg_cutlevel2 ){
            # $msg_cutlevel2 defines writing to SYSLOG. 3 means Errors (Severe and terminal messages always whould be print STDERRed)
            if( $severity<4 ){
               print SYSLOG "$message\n";
            } else {
               # special treatment of serious messages
               print SYSLOG "$delim\n$message\n$delim\n";
            }
         }
         if( $severity >= $msg_cutlevel1 ){
            # $msg_cutlevel1 defines writing to STDIN. 3 means Errors (Severe and terminal messages always whould be print STDERRed)
            if( $severity<2 ){
               print STDERR "$message\n";
            } else {
               print STDERR "$delim\n$message\n$delim\n";
            }
         }
         return;
      } # $severity<3
# severity=3 -- error code T
# Here we processing error code 'T' which means "issue error summary and terminate"
# termination will be using die if the message suffix is "A" -- Nov 12, 2015
#

my $summary;
my $counter;
my $delta_chunks;
      #
      # We will put the most severe errors at the end and make 15 sec pause before  read them
      #
      out($message);
      for( $counter=1; $counter<length('WEST'); $counter++ ){
         next unless( $ercounter[$counter] );
         $summary.=" ".substr('WEST',$counter,1).": ".$ercounter[$counter];
      } # for
      out("\n\n=== SUMMARY OF ERRORS: $summary\n");
      out($_[2]);
      if( $ercounter[2] + $ercounter[3] + $ercounter[4] ){
         # print STDERR errors & severe errors
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
      if( $error_suffix eq 'A' ){
         # messages with Eroor code TA couse abend
         die("Can't continue");
      }
      exit;
} # logme

#
# Output message to both log and STDERR
#
sub out
{
      if( scalar(@_)==0 ){
         print STDERR;
         print SYSLOG;
         return;
      }
      print STDERR "$_[0]\n";
      print SYSLOG "$_[0]\n";
}

sub step
{
      $DB::single = 1;
}
