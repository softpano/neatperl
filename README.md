# neatperl
Prettyprinter for Perl

Neatperl  a simple Perl  prettyprinter based of "fuzzy" determination of nesting level 
 
Nikolai Bezroukov, 2019-2020,   Licensed under Perl Artistic license 

For more complete and, most probably, more current info http://www.softpanorama.org/Utilities/Beautifiers/neatperl.shtml

Pretty printer Neatperl can be called a "fuzzy" pretty-printer. If does not perform full lexical analysis (which for Perl is complex task despite the fact the lexical level in Perl, unlike bash, is well defined). Instead it relies on analysis of a limited context of each line (prefix and suffix) to "guess" correct nesting level.  It does not perform any reorganization of the text other then re-indentation. 

Lines starting with the first column are not indented. 

For reasonable Perl style typically found in production scripts the results are quite satisfactory. Of course, it will not work for compressed or obscured code.
You can correct nesting level in case of necessity using psudo-comments, 

Currently two types of pseudo-comments (pragmas) are implemented. Using them you can control the formatting and correct formatting errors. All pesudocomments should start at the beginning of the line. No leading spaces allowed.

1. Switching formatting off and on for the set of lines. This idea is similar to HERE documents allowing to skip portions of the script which are too difficult to format correctly. One example is a here statement with indented lines when re-indenting them to the current nesting level (which is the default action of the formatter)  is undesirable.  
  #%OFF -- (all capitals, should be on the only text in the line, starting from the first position) stops formatting, All lines after this directive are not processed and put into listing and formatted code buffer intact
  #%ON -- (all capitals, the  only text on the line starting from the first position with no leading blanks) resumes formatting

2. Correcting nesting level. The directive is "#%NEST" which has  several forms (more can be added if necessary ;-):  

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

1. All control statements should start at the first position of the line. No leading blanks are allowed. 

2. No spaces between NEST and = or NEAT and ++/-- are allowed.

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
