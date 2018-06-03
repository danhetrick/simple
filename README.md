# simple

SIMPLE (Simple Interpolated Mark-uP LanguagE) is a procedural, Turing-complete programming language designed to be easy to teach beginners to computer programming.  It uses a two-pronged paradigm:

  • Rather than using C's brackets or Python's indentation to delimit code blocks, SIMPLE uses a style derived from HTML and XML:  markup tags. 
  
  • Unlike other high-level programming languages, SIMPLE strives to be as close to natural English as possible.  Other than the symbols required to do math, for markup tags, and for interpolation, SIMPLE uses no symbolic constructs.  Statement should state, plainly, what they do in English, with a minimum of punctuation or non-numeric symbols;  instead of C's "if(i==3){", which is difficult for non-programmers to read, SIMPLE would use "if $i equals 3", an easier construct to read for non-programmers.
 
SIMPLE was designed for the "HTML Generation";  that is, people who are familiar with HTML and markup tags, yet are not familiar with programming.  It is not a complete application solution.  SIMPLE is limited by design;  it's designed to be a teaching tool.   sim.pl, the SIMPLE compiler, takes in a SIMPLE program (a specific kind of XML document, detailed below) and compiles it into stand-alone Perl (the output program requires only a default installation of Perl).  The compiler also checks programs for correct syntax, returning the line number of any errors it finds.  It can't detect all errors;  errors involving user or system input are displayed when the compiled program is executed, returning the line number in the original SIMPLE program where the error occurred.  These two features make debugging SIMPLE programs fairly easy;  runtime error messages (which include the line number in the SIMPLE program where the error occurred) are inserted into the compiled program automatically making debugging even easier.

There are three things this programming language is designed to teach:

  • Variables.  Almost every programming language uses this concept. 
  
  • Interpolation2.  Many common programming languages, like PHP and Perl, use some sort of interpolation system.  Even C/C++ uses one (for an example, see the standard library function printf). 
  
  • Variable Scoping3.  A feature of every major programming language and almost none of the beginner programming languages.
  
SIMPLE was heavily influenced by two different languages:  Perl and XML.  The interpolation system is borrowed from Perl, allowing variables to be interpolated in strings using the $ sign (see Variables and Interpolation, in the manual).  The overall syntax is borrowed from XML;  all code blocks4 are in the form of XML tags.  I view this language as a blend of the power of string manipulation in Perl with the parse-ability of XML.  Support for regular expressions (also known as a "regex") is not included;  regular expressions are difficult to explain to experienced programmers, and as SIMPLE is a teaching language we don't need to bog down users with them (they can always learn them later).  Likewise, there are only two markup tags users must learn:  import and subroutine.
SIMPLE strives to be easily read by non-programmers.  To that end, SIMPLE limits its syntax to help users write readable code.

Limitations include:

  • Nested flow control blocks are forbidden.  An if block can't contain another if block.  while blocks can't contain another while block. 
  
   • One, and only one, command per line of code.  Code with multiple commands per line can be difficult for non-programmers to read or understand. 
   
   • Commands are as close to natural English as possible.  A non-programmer should be able to figure out what a program does by reading its source code.

