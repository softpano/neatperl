# neatperl
Prettyprinter for Perl
  Neatperl -- a simple bash prettyprinter 
 based of "fuzzy" determination of nesting level 
  Nikolai Bezroukov, 2019,   Licensed under Perl Artistic license
Version 0.4 (Sept 3, 2019)

For more complete and, most probably, more current info http://www.softpanorama.org/Utilities/Beautifiers/neatperl.shtml

Pretty printer Neatperl can be called a "fuzzy" pretty-printer. If does not perform full lexical analysis (which for bash is impossible  as BASH does not have lexical level defined). Instead it relies on analysis of a limited context of each line (prefix and suffix) to "guess" correct nesting level.  It does not perform any reorganization of the text other then re-indentation. 
  For reasonable bash style typically found in production scripts the results are quite satisfactory. Of course, it will not work for compressed or obscured code.
This is a relatively novel approach as typically prettyprinter attempt to implement full lexical analysis of the language with some elements of syntax analysis, see for example my (very old) NEATPL pretty printer ( http://www.softpanorama.org/Articles/Oldies/neatpl.pdf  ) -- one of the first first program that I have written that got widespread use,  or Perltidy. 
The main advantage is that such approach allows to implement pretty capable pretty printer is less then 500 lines of Perl source code with around 200 lines implementing  the formatting algorithm. Such small scripts are more maintainable and have less chances to "drop dead" and became abandonware after the initial author lost interests and no longer supports the script.
Neatperl does not depends on any non-standard Perl modules and it's distribution consists just of two items: the script itself and the readme file.  This is an advantage as installing Perl modules in corporate environment often is not that simple and you can run into some bureaucratic nightmare.  also with  many modules used you always risk compatibility hell. It is sad that Perl does not have zipped format as jar files for Java which allow to package the program with dependencies as a single file. but we have what we have
Another huge advantage is the this is  a very safe approach, which normally does not (and can not) introduces any errors in bash code with the exception of indented here lines which might be "re-indented" based on the current nesting.  As Perl have very complex lexical structure which in not a context free grammar its parsing  represent a daunting task and it can never be guaranteed to be  correct.  Which means that "fuzzy" prettyprinter approach  this is a safer approach for such language but even it can mangle some  parts of the script such as HERE strings in case of some "too inventive" delimiters used (in Perl the delimiter can be defined via double quotes string that can contain variables and as such is not known at compile time.)  Perverted programmers also can define such string using q notation. 
There is no free lunch, and such limited context approach means that sometimes (rarely) the nesting level can be determined incorrectly.  There also might be problem with determination of the correct end of of HERE literals or q literalscontaing Perl code. Missed HERE string  that  have non zero fixed indent can be shifted left of right which might be not a good thing  (HERE stings with zero indent are safe). So fuzzy prettyprinter is best for you oqn scrpts in which you can maintain a safe Perl style which is prettyprinter  friendly. For scripts written by other people your mileage can vary but even in  this case it is a great diagnostic tools and helps to understand the scripts written by other people.  
To correct this situation three pseudo-comments (pragmas)  were introduced using which you can control the formatting and correct formatting errors. All pesudocomments should start at the beginning of the line. No leading spaces allowed. 
 Currently Neatperl allows three types of pseudo-comments:
Switching formatting off and on for the set of lines. This idea is similar to HERE documents allowing to skip portions of the script which are too difficult to format correctly. One example is a here statement with indented lines when re-indenting them to the current nesting level (which is the default action of the formatter)  is undesirable.  
  #%OFF -- (all capitals, should be on the only text in the line, starting from the first position) stops formatting, All lines after this directive are not processed and put into listing and formatted code buffer intact
  #%ON -- (all capitals, the  only text on the line starting from the first position with no leading blanks) resumes formatting

Correcting nesting level if it was determined incorrectly. The directive is "#%NEST" which has  several forms (more can be added if necessary ;-):  
Set the current nesting level to specified integer 
 #%NEST=digit --
Increment 
#%NEST--
Decrement 
#%NEST--
For example, if  Neatperl did not recognize correctly the  point of closing of a particular control structure you can close it yourself with the directive
#%NEST-- 
or 
#%NEST=0 
NOTES: 
Again, all control statement should start at the first position of the line. No leading blanks are allowed. 
No spaces between NEST and = pr NEAT and ++/-- are allowed.
Also you can arbitrary increase and decrease indent with this directive
As  Neatperl maintains stack of control keywords it reorganize it also produces some useful diagnostic messages, which in many cases are more precise then  bash diagnostics. 
For most scripts Natperl is able to determine that correct nesting level and proper indentation. Of course, to be successful, this approach requires a certain (very reasonable) layout of the script. the main requirement is that multiline control statements should start and end on a separate line.  
One liners (control statements which start and end on the same line) are acceptable 
While any of us saw pretty perverted formatting style in some scripts this typically is an anomaly in production quality scripts and most production quality scripts display very reasonable control statements layout, the one that is expected by this pretty printer.  
But again that's why I called this pretty printer "fuzzy"
For any script compressed to eliminate whitespace this approach is not successful
INVOCATION
 neatperl [options] [file_to_process]
or 
 neatperl -f [other_options] [file_to_process] # in this case the text will be replaced with formatted text, 
                                              # backup will be saved in the same directory
or 
cat file |  neatperl -p [other_options] > formatted_text # invocation as pipe
OPTIONS
  -h --  help
  -t number -- size of tab (emulated with spaces). The default is 3
  -f -- "in place" formatting of a file: write formatted text into the same files creating backup
  -p -- work as a pipe
   -v -- - provides additional warnings about non-balance of quotes and round parentheses. You can specify verbosity level
0 -- only serious errors are displayed
1 -- serious errors and errors are displayed
2 -- serious errors, errors and warnings are displayed
PARAMETERS
  1st -- name of the file to be formatted
