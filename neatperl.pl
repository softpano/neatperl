#!/usr/bin/perl
#:: neatperl version 1.00 (Oct 10, 2019) -- Fuzzy prettyprint for Perl scripts
#:: Nikolai Bezroukov, 2019.
#:: Licensed under Perl Artistic license
#::
#:: This is a fuzzy prettyprinter in a sense that the netsting level is determined using heuristic methods:
#::    Only prefix and suffix of the line are analysed to determine the nesting level.
#::    In most cases this is sucessful approach and in a few case when it is not it is easovy corrected using pragma %NEST
#:: For example
#::    #%NEST=2
#::
#:: To be sucessful, this approach requres a certain (very resonable) layout of the script. That's why we use the term "fuzzy".
#:: It works with most production script I encounter. But there some notable exceptions. For example, for script compressed
#:: to eliminate whitespace this approach is clearly can't be successful
#::
#:: --- INVOCATION:
#::
#::   neatperl [options] [file_to_process]
#::
#::--- OPTIONS:
#::
#::    -v -- display version
#::    -h -- this help
#::    -t number -- size of tab (only spaces are used for indentation in NeatPerl, no tabs)
#::    -f  -- written formatted test into the same file creating backup
#::    -w --  provide additional warnings about non-balance of quotes and round parentheses
#::
#::--- PARAMETERS:
#::    1st -- name of  file
#::
#::    NOTE: With option -p the program can be used as a stage for the pipe. FOr example#::
#::       cat my_script.sh | neatperl -p > my_script_formatted.sh
#
#--- Development History
#
# Ver      Date        Who        Modification
# ====  ==========  ========  ==============================================================
# 0.10  2012/07/12  BEZROUN    Initial implementation
# 0.20  2012/07/14  BEZROUN    Parameter processing added
# 0.30  2019/08/30  BEZROUN    logic improved based on experience with writing neatperl
# 0.40  2019/08/31  BEZROUN    Formatter listing redirected to STDERR. The ability to work as a pipe
# 0.50  2019/09/03  BEZROUN    Checking of re-formatted script via  perl -cw
# 0.60  2019/09/14  BEZROUN    Readability option (-r) implemented
# 0.61  2019/09/17  BEZROUN    Minor changes and cleanup of logging infrastructure.
# 0.70  2019/09/19  BEZROUN    Keyword sub in first position iv viewed as the subrotime and checked for nesting level 0.
# 0.70  2019/09/19  BEZROUN    Directive #%NEST=0 produces error message if calculated NEST not equal to zero.
# 0.71  2019/10/04  BEZROUN    Severity handing in logme improved: if code does not exist just print the message.
# 0.72  2019/10/04  BEZROUN    autocommit made more flexible: commits only if the source code changed and debug level is non zero
# 0.80  2019/10/07  BEZROUN    Simple code stats added to summary. Step toward producing  complexity metric
# 0.81  2019/10/08  BEZROUN    Some refactoring to reduce maximum nesting level
# 1.00  2019/10/09  BEZROUN    Testing completed and was sucessful.
# 1.10  2019/10/10  BEZROUN    allowed tail commments like:  }else{ #This is abad  style of commenting but it happened
# 1.20  2019/10/14  BEZROUN    Simple XREF table is added -- option -X
# 1.30  2020/10/26  BEZROUN    A couple of minor changes
#START ======================================================================================================================
   use v5.10;
   use warnings;
   use strict 'subs';
   use feature 'state';
   use Getopt::Std;

   $VERSION='1.30';
   $debug=0; # 0 production mode 1 - development/testing mode. 2-9 debugging modes
   $breakpoint=-1;
   $STOP_STRING=''; # In debug mode gives you an ability to switch trace on any type of error message for example S (via hook in logme).


# INTERESTING, VERY NEAT IDEA: you can switch on tracing from particular line of source ( -1 to disable)

   $SCRIPT_NAME=substr($0,rindex($0,'/')+1);
   if( ($dotpos=index($SCRIPT_NAME,'.'))>-1 ) {
      $SCRIPT_NAME=substr($SCRIPT_NAME,0,$dotpos);
   }
   $use_git_repo='';
   #$OS=$^O; # $^O is built-in Perl variable that contains OS name
   $HOME=$ENV{'HOME'};  # $HOME/Archive is used for backups

   $LOG_DIR='/tmp/'.ucfirst($SCRIPT_NAME);
   $tab=3;
   $write_formatted=0; # flag that dremines if we need to write the result into the file supplied.
   $write_pipe=0;

   $readability_plus=0;
   %keyword=('if'=>1, 'elsif'=>1,'while'=>1,'unless'=>1, 'until'=>1,'for'=>1,'foreach'=>1,'given'=>1,'when'=>1,'default'=>1);

   logme('D',1,2); # E and S to console, everything to the log.
   banner($LOG_DIR,$SCRIPT_NAME,'Simple Perl prettyprinter',30); # Opens SYSLOG and print STDERRs banner; parameter 4 is log retention period
   get_params(); # At this point debug  flag can be reset
   if( $debug>0 ){
      logme('D',2,2); # Max verbosity
      print STDERR "ATTENTION!!! $SCRIPT_NAME is working in debugging mode $debug with autocommit of source to $HOME/Archive\n";
      autocommit("$HOME/Archive",$use_git_repo); # commit source archive directory (which can be controlled by GIT)
   }

#
# Main loop initialization variables
#
   $NewNest=$CurNest=$MaxNest=0; # variables for nesting level
   $CodeLinesNo=$TotalSubNo=$TotalBlockNo=0; # code metrics
   $lineno=$fline=0; # fline is the last line number in formatted code array
   $here_delim="\n"; # this impossible combination means uninitialised
   $noformat=0;
   $InfoTags='';
   $nest_corrections=0;
   @SourceText=<STDIN>; # slurp source
#
# MAIN LOOP
#
   for( $lineno=0; $lineno<@SourceText; $lineno++  ){
      $line=$SourceText[$lineno];
      $offset=0;
      chomp($line);
      $intact_line=$line;
      if( $lineno == $breakpoint ){
         $DB::single = 1
      }
      if( substr($line,-1,1) eq "\r" ){
         chop($line);
      }
      # trim traling blanks, if any
      if( $line=~/(^.*\S)\s+$/ ){
         $line=$1;
      }

      #
      # Check for HERE line
      #

      if( $noformat ){
         if( $line eq $here_delim ){
            $noformat=0;
            $InfoTags='';
         }
         process_line(-1000);
         next;
      }

      if( $line =~/<<['"](\w+)['"]$/ ){
         # start of HERE block
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
            correct_nesting()
         }
         process_line(-1000);
         next;
      }
      # blank lines should not be processed
      if( $line =~/^\s*$/ ){
         process_line(-1000);
         next;
      }
      if( substr($line,0,1) eq '=' && $line ne '=cut' ){
         $noformat=1;
         $InfoTags='POD';
         $here_delim='=cut';
         process_line(-1000);
         next;
      }
      if( $line eq '__END__' || $line eq '__DATA__' ){
         $CodeLinesNo--;
         logme('E',"Non zero nesting encounted for $line");
         if( $CurNest>0) {
            $InfoTags='} ?';
         }else{
            $InfoTags='{ ?';
         }
         $noformat=1;
         $here_delim='"'; # No valid here delimiter in this case !
         $InfoTags='DATA';
         process_line(-1000);
         next;
      }
      $CodeLinesNo++;
      if( $line =~ /^sub\s+(\w+)/ ){
         $SubList{$1}=$lineno;
         $TotalSubNo++;
         if( $CurNest>0) {
            $InfoTags='} ?';
         }elsif( $CurNest<0 ){
            $InfoTags='{ ?';
         }
         if( $CurNest !=0 ){
            $CurNest=$NewNest=0;
            $nest_corrections++;
            logme('E',"Non zero nesting encounted for subroutine definition $1");
         }
      }

      # trim leading blanks
      if( $line=~/^\s*(\S.*$)/ ){
         $line=$1;
      }

      # comments start in the first non blank position
      $first_sym=substr($line,0,1);
      if( substr($line,0,1) eq '#' ){
         $CodeLinesNo--;
         process_line(0);
         next;
      }
      # Should be enhanced later blocking increase of nesting for sub
      if( $first_sym eq '{' ){
         $TotalBlockNo++;
         $NewNest++;
      }elsif( $first_sym eq '}' ){
         $NewNest--;
         $offset=-1;
      }
      # Step 2: check the last symbol for "{"
      # NOTE: comments are prohibited on such lines
      $last_sym=substr($line,-1,1);
      if( $last_sym eq '{' && length($line)>1 ){
         $TotalBlockNo++;
         $NewNest++;
      }# if
      if( $line=~/\{\s*\#\s*\w+/ ){
         # tail comments are now allowed -- NNB Oct 10, 2019
         $TotalBlockNo++;
         $NewNest++;
      }# if

      # Check if we can nest this line (lines starting fromnt he first position are not nestable))
      unless( substr($intact_line,0,1) =~/\s/ ){
         $offset=-1000;
      }
      if( $MaxNest < $NewNest ){ $MaxNest=$NewNest; }
      process_line($offset);

   } # while
#
# Epilog
#
   code_metric();
   xref();
   if( $CurNest !=0 || $nest_corrections > 0 ){
      ( $write_formatted >0 || $write_pipe > 0  ) && logme('S',"Writing of formatted code is blocked due to errors detected");
      logme('T',"Script might have errors; diagnistics follows."); # this terminates script.
   }elsif( $write_formatted >0 || $write_pipe > 0  ){
      write_formatted_code(); # that terminated the program
   }else{
      logme('T',"Normal completion of the program in listing only mode"); # this terminates script.
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
      $prefix=sprintf('%4u %3d %4s',$lineno, $CurNest, $InfoTags);
      if( substr($intact_line,0,1) =~ /\S/ ){
         $spaces='';
      }elsif( ($CurNest+$offset)<0 || $CurNest<0 ){
         $spaces='';
      }else{
         $spaces= ' ' x (($CurNest+$offset+1)*$tab);
      }
      if( $readability_plus==1 && $line=~/^(\}?\w+)/ ){
         # should affect only line starting with defined keywords
         $first_word=$1;
         if( exists($keyword{$first_word}) ){
            substr($line,0,length($first_word))='';
            if( $line=~/^(\s+\(\s*)/ ){
               substr($line,0,length($1))=''; # remove ( with surrounding white spaces
               $line=$first_word.'( '.$line; #restore the line
               $line =~ s/\s*\)\s+\{$/ ){/;
            }else {
               $line=$first_word.$line;
            }
         }
      }
      print STDERR "$prefix | $spaces$line\n";
      if( $write_formatted > 0 ){
         $FormattedSource[$fline++]="$spaces$line\n";
      }
      $CurNest=$NewNest;
      if( $noformat==0 ){ $InfoTags='' }
}
sub code_metric
{
my @subs_list;
      $lineno--;
      out("\nSOURCE CODE STATS:\n\tTotal lines $lineno; Of them without comments: $CodeLinesNo; Max nesting: $MaxNest; Internal subs: $TotalSubNo; Blocks: $TotalBlockNo\n");
      if( $MaxNest>4) {
         out("Excessive nesting, consider refactoring");
      }
      out("\nLIST OF SUBROUTNES\n");
      my $i=0;
      foreach $s (keys(%SubList)) {
         $sub_list[$i++]=$s.': '.$SubList{$s};
      }
      @sub_list=sort @sub_list;
      for( $i=0; $i<@sub_list; $i++ ){
       out("\t$i $sub_list[$i]");
      }
}
sub correct_nesting
{
      if( $line =~ /^#%NEST=(\d+)/ ){
         if( $CurNest != $1 ) {
            logme('E',"Nest is $CurNest instead of $1. Reset to $1");
            $CurNest=$NewNest=$1; # correct current nesting level
            $InfoTags="=$CurNest";
         }else{
            $InfoTags="OK $CurNest";
         }
      }elsif( $line =~ /^#%NEST++/ ){
         $CurNest=$NewNest=$1+1; # correct current nesting level
         $InfoTags='+1';
      }elsif( $line =~ /^#%NEST--/ ){
         $CurNest=$NewNest=$1+1; # correct current nesting level
         $InfoTags='-1';
      }elsif( $line =~ /^#%ZERO\?/ ){
         if( $CurNest == 0 ) {
            $InfoTags="OK $CurNest";
         }else{
            $InfoTags="??";
            logme('E',"Nest is $CurNest instead of zero. Reset to zero");
            $CurNest=$NewNest=0;
            $nest_corrections++;
         }
      }
}

sub write_formatted_code
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
         print SYSFORM @FormattedSource;
         close SYSFORM;
         `perl -cw $fname.neat`;
         if(  $? > 0 ){
            logme('T',"Checking reformatted code via perl -cw produced some errors (RC=$?). The original file left intact. Reformatted file is $fname.neat");
         }else{
            close STDIN;
            `mv $fname.neat $fname`;
            logme('T',"Source is now reformatted"); # this terminates script.
         }
      }elsif( $write_pipe ){
         print @FormattedSource;
         logme('T',"Source is now reformatted"); # this terminates script.
      }
      logme('T',"Normail completion of the program"); # this terminates script.
}
sub xref
{
my $output_file="$LOG_DIR/$fname.xref";
my ($line,$i,$k,$var, %dict, %type, @xref_table);
   open (SYSFORM,'>',$output_file ) || abend(__LINE__,"Cannot open file $output_file for writing");
   for( $i=0; $i<@SourceText; $i++ ){
      $line=$SourceText[$i];
      next if (substr($line,0,1) eq '#' || $line=~/(\s+)\#/ );
      chomp($line);
      while( ($k=index($line,'$'))>-1 ){
         $line=substr($line,$k+1);
         next unless( $line=~/^(\w+)/ );
         next if( $1 eq '_' || $1 =~[1-9] );
         $k+=length($1)+1;
         $var='$'.$1;
         if($line=~/\w+\s*=\s*[+-]?\d+/ ){
            unless(exists($type{$var})) {$type{$var}='int';}
         }elsif( $line=~/\w+\s*[+-=<>!]?=\s*(index|length)/ ){
            unless( exists($type{$var}) ) {$type{$var}='int';}
          }elsif( $line=~/\w+\s*[+-=<>!]?=\s*[+-]?\d+/ ){
            unless( exists($type{$var}) ) {$type{$var}='int';}
         }elsif( $line=~/\w+\s*\[.+?\]?\s*(\$\w+)/ && exists($type{$1}) && $type{$1} eq 'int' ) {
            unless( exists($type{$var}) ) {$type{$var}='int';};
         }elsif( $line=~/\w+\s*\[.+?\]?\s*[+-=<>!]=\s*\d+/ ){
            #Array
            unless( exists($type{$var}) ) {$type{$var}='int';}
         }elsif( $line=~/\w+\s*\{.+?\}\s*[+-=<>!]?=\s*\d+/ ){
            #Hash
            unless( exists($type{$var}) ) {$type{$var}='int';}
         }

         if( exists($dict{$var}) ){
            $dict{$var}.=', '.$i;
         }else{
           $dict{$var}.=$i;
         }
     }
   }
   print STDERR "\n\nCROSS REFERENCE TABLE\n\n";
   $i=0;
   foreach $var (keys(%dict)) {
      $prefix=( exists($type{$var}) ) ? $type{$var} : 'str';
      $xref_table[$i]="$prefix $var $dict{$var}\n";
      $i++;
   }
   @xref_table=sort(@xref_table);
   for( $i=0; $i<@xref_table; $i++ ){
      print STDERR "$xref_table[$i]\n";
      print SYSFORM "$xref_table[$i]\n";
   }
   close SYSFORM;
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
         }else{
            die("Wrong value of option -t (tab size): $options('t')\n");
         }
      }

      if(  exists $options{'b'}  ){
         if( $options{'b'}>0  && $options{'t'}<1000 ){
            $breakpoint=$options{'b'};
         }else{
            die("Wrong value of option -b (line for debugger breakpoint): $options('b')\n");
         }
      }

      if(  exists $options{'d'}  ){
         if( $options{'d'} =~/^\d$/ ){
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
            die ("File $fname does not exists");
         }
         open (STDIN, "<$fname") || abend("Unable to open file $fname");
      }else{
         $args=join(' ', @ARGV);
         die ("Too many arguments: $args")
      }

}
#
###================================================= NAMESPACE sp: My SP toolkit subroutines
#
#
# Create backup and if there were changes automatically commit script to GIT repository.
#
#package sp;
sub autocommit
{
# parameters
my $archive_dir=$_[0]; # typically home or $HOME/bin
my $use_git_repo=$_[1]; # GIT dir
#
#  Local vars
#
my $script_name=substr($0,rindex($0,'/')+1);
my $script_timestamp;
my $script_delta=1;
      ( ! -d $archive_dir ) && `mkdir -p $archive_dir`;
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
      if ($script_delta) {
         `cp -p $0 $archive_dir/$script_name`;
          ($use_git_repo) && `git commit $0`; # autocommit
      }
} # autocommit

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
# Terminate program (variant without mailing). message_proxix should be established at this point via call to logme.
#
sub abend
{
my $message;
my ($package, $filename, $lineno) = caller; # detect called lineno
      if( scalar(@_)==0 ){
         $message=$MessagePrefix.$lineno."T  ABEND at $lineno. No message was provided. Exiting.";
      }else{
         $message=$MessagePrefix.$lineno."T $_[0]. Exiting ";
      }
#  Syslog might not be availble
      out($message);
      #[EMAIL] banner('ABEND');
      die('Internal error');

} # abend


#
# Open log and output the banner; if additional arguments given treat them as subtitles
#        depends of two variable from main namespace: VERSION and debug
sub banner {
#
# Sanity check
#
state $logfile;
      if( scalar(@_)<4 && $_[0] eq 'ABEND' ){
         close SYSLOG;
         #[EMAIL]`cat $logfile | mail -s "[ABEND for $HOSTNAME/$SCRIPT_NAME] $_[0] $PrimaryAdmin`;
         return;
      }
#
# Decode obligatory arguments
#
state $my_log_dir=$_[0];
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

      $logfile="$my_log_dir/$script_name.$logstamp.log";
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
state $MessagePrefix='';

#
# special cases -- ercode "D" means set msglevel1 and msglevel2, ' ' means print STDERR in log and console -- essentially out with messsage header
#

      if( $error_code eq 'D' ){
         # NOTE You can dynamically change verbosity within the script by issue D message.
         # Set script name and message  prefix
         if( $MessagePrefix eq '') {
            $MessagePrefix=substr($0,rindex($0,'/')+1);
            $MessagePrefix=substr( $MessagePrefix,0,4);
         }
         $verbosity1=$_[1];
         $verbosity2=$_[2];
         $msg_cutlevel1=length("WEST")-$verbosity1-1; # verbosity 3 is max and means 4-3-1 =0  -- the index corresponding to code 'W'
         $msg_cutlevel2=length("WEST")-$verbosity2-1; # same for log only (like in MSGLEVEL mainframes ;-)
         return;
      }
      unless( $error_code ){
         # Blank error code is old equivalent of out: put obligatory message on console and into log
         out($message);
         return;
      }
#
# detect caller lineno
#
      my ($package, $filename, $lineno) = caller;
#
# Generate diagnostic message from error code, line number and message (optionally timestamp is suffix of error code is T)
#
      $message="$MessagePrefix\-$error_code$lineno: $message";
      my $severity=index("west",lc($error_code));
      if( $severity == -1 ){
         out($message);
         return;
      }

      $ercounter[$severity]++; #Increase messages counter  for given severity (supressed messages are counted too)
      $ermessage_db[$severity] .= "\n\n$message"; #Error history for the ercodes E and S
      return if(  $severity<$msg_cutlevel1 && $severity<$msg_cutlevel2 ); # no need to process if this is lower then both msglevels
#
# Stop processing if severity is less then current msglevel1 and msglevel2
#
      if( $severity < 3 ){
         # WES but not T
         if( $severity >= $msg_cutlevel2 ){
            # $msg_cutlevel2 defines writing to SYSLOG. 3 means Errors (Severe and terminal messages always whould be print STDERRed)
            if( $severity<2 ){
               print SYSLOG "$message\n";
            }else{
               # special treatment of serious messages
               print SYSLOG "$delim\n$message\n$delim\n";
            }
         }
         if( $severity >= $msg_cutlevel1 ){
            # $msg_cutlevel1 defines writing to STDIN. 3 means Errors (Severe and terminal messages always whould be print STDERRed)
            if( $severity<2 ){
               print STDERR "$message\n";
            }else{
               print STDERR "$delim\n$message\n$delim\n";
            }
         }
         if( length($::STOP_STRING)>0 && index($::STOP_STRING,$error_code) >-1 ){
            $DB::single = 1;
         }
         return;
      } # $severity<3

# == Processing severity=3 -- error code T ==
#    Error code 'T' which means "Issue error summary and normally terminate"
#    Termination will be using die if the message suffix is "A" -- Nov 12, 2015
#

my $summary='';

      #
      # We will put the most severe errors at the end and make 15 sec pause before  read them
      #
      out("$message");
      for( my $counter=1; $counter<length('WES'); $counter++ ){
         if( defined($ercounter[$counter]) ){
            $summary.=" ".substr('WES',$counter,1).": ".$ercounter[$counter];
         }else{
            $ercounter[$counter]=0;
         }
      } # for
      ($summary) && out("\n=== SUMMARY OF ERRORS: $summary\n");
      if( $ercounter[1] + $ercounter[2] ){
         # print STDERR errors & severe errors
         for(  $severity=1;  $severity<3; $severity++ ){
            # $ermessage_db[$severity]
            if( $ercounter[$severity] > 0 ){
               out("$ermessage_db[$severity]\n\n");
            }
         }
         ($ercounter[2]>0) && out("\n*** PLEASE CHECK $ercounter[2] SERIOUS MESSAGES ABOVE");
      }

#
# Compute RC code: 10 or higher there are serious messages
#
      my $rc=0;
      if( $ercounter[2]>0 ){
         $rc=($ercounter[2]<9) ? 10*$ercounter[2] : 90;
      }
      if( $ercounter[1]>0 ){
         $rc=($ercounter[1]<9) ? $ercounter[2] : 9;
      }
      exit $rc;
} # logme

#
# Output message to both log and STDERR
#
sub out
{
      if( scalar(@_)==0 ){
         say STDERR;
         say SYSLOG;
         return;
      }
      say STDERR $_[0];
      say SYSLOG $_[0];
}

sub step
{
      $DB::single = 1;
}
