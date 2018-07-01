# Summary

**SIMPLE** (**S**imple **I**nterpolated **M**ark-u**P** **L**anguag**E**) is a procedural, Turing-complete programming language designed to be easy to teach beginners to computer programming.  It uses a two-pronged paradigm:

* Rather than using C's brackets or Python's indentation to delimit code blocks, **SIMPLE** uses a style derived from HTML and XML:  markup elements.
* Unlike other high-level programming languages, **SIMPLE** strives to be as close to natural English as possible.  Other than the symbols required to do math, for markup elements, and for interpolation, **SIMPLE** uses no symbolic constructs.  Statement should state, plainly, what they do in English, with a minimum of punctuation or non-numeric symbols;  instead of C's `if(i==3){`, which is difficult for non-programmers to read, **SIMPLE** would use `if $i equals 3`, an easier construct to read for non-programmers.

**SIMPLE** was designed for the "HTML Generation";  that is, people who are familiar with HTML and markup elements, yet are not familiar with programming.  It is not a complete application solution.  **SIMPLE** is limited by design;  it's designed to be a teaching tool.   `sim.pl`, the **SIMPLE** compiler, takes in a **SIMPLE** program (a specific kind of XML document, detailed below) and compiles it into stand-alone Perl (the output program requires only a default installation of Perl).  The compiler also checks programs for correct syntax, returning the line number of any errors it finds.  It can't detect all errors;  errors involving user or system input are displayed when the compiled program is executed, returning the line number in the original **SIMPLE** program where the error occurred.  These two features make debugging **SIMPLE** programs fairly easy;  runtime error messages (which include the line number in the **SIMPLE** program where the error occurred) are inserted into the compiled program automatically making debugging even easier.

There are three things this programming language is designed to teach:

* _**Variables**_.  Almost every programming language uses this concept.
* _**Interpolation**_.  Many common programming languages, like PHP and Perl, use some sort of interpolation system.  Even C/C++ uses one (for an example, see the standard library function `printf`).
* _**Variable Scoping**_.  A feature of every major programming language and almost none of the beginner programming languages.

**SIMPLE** was heavily influenced by two different languages:  Perl and XML.  The interpolation system is borrowed from Perl, allowing variables to be interpolated in strings using the `$` sign (see Variables and Interpolation, below).  The overall syntax is borrowed from XML;  all code blocks are in the form of XML elements.  I view this language as a blend of the power of string manipulation in Perl with the parse-ability of XML.  Support for regular expressions (also known as a "regex") is not included;  regular expressions are difficult to explain to experienced programmers, and as **SIMPLE** is a teaching language we don't need to bog down users with them (they can always learn them later).  Likewise, there are only two markup elements users must learn:  `import` and `subroutine`.

**SIMPLE** strives to be easily read by non-programmers.  To that end, **SIMPLE** limits its syntax to help users write readable code.  Limitations include:

* _**Nested flow control blocks are forbidden**_.  An if block can't contain another if block.  while blocks can't contain another while block.
* _**One, and only one, command per line of code**_.  Code with multiple commands per line can be difficult for non-programmers to read or understand.
* _**Commands are as close to natural English as possible**_.  A non-programmer should be able to figure out what a program does by reading its source code.

# The SIMPLE Code Compiler

The **SIMPLE** Code Compiler is a Perl program named `sim.pl`.  All **SIMPLE** programs are compiled to a stand-alone Perl program;  that means that, once a **SIMPLE** program is compiled, it will run on any platform that Perl runs on, and does not require `sim.pl` to run.

If `sim.pl` is ran from the command-line with no arguments, basic usage information is displayed:

	localhost:~ user$ perl sim.pl SIMPLE Code Compiler 0.00154 (dragon)
	Usage: sim.pl [OPTIONS] FILENAME
	Options:
	-h(elp) Display this text
	-v(erbose) Displays additional information while compiling
	-o(utput) FILENAME Sets the output filename; default is "out.pl"
	-d(efault) SUBROUTINE Sets the default subroutine; default is "main"
	-e(xecutor) Strips executor stub code from output
	-s(tdout) Prints output to STDOUT instead of a file
	-i(nclude) Includes the original source into the compiled source
	localhost:~ user$

To compile a **SIMPLE** program, pass it as the only argument to `sim.pl`.  By default, this will create a new file name `out.pl` which contains the output Perl code.  If you want to write the compiled code to a different file, use the `-o` option.

If any syntax errors in the code are found, the errors are displayed to the user and compilation is aborted.  Where the error was in the program is reported to the user;  however, the line number reported is relative to what subroutine the error is in.  For example, take a look at the following program:

	  <subroutine name="main">
	1 	print "This program has an error in it!"
	2 	this_command_doesnt_exist
	  </subroutine>

The command on line 3 (`this_command_doesnt_exist`) will throw an error, as the command, much like its name, doesn't exist.  However, when we try to compile it:

	localhost:~ user$ perl sim.pl buggy_program.sim
	1 error found!
	Error in 'main' on line 2:  Statement "this_command_doesnt_exist" not recognized
	localhost:~ user$

Since error occurs on line 2 of the subroutine, that's the line number that is reported.

# Example sim.pl Usage

Let's write a basic "hello world" program in **SIMPLE**.  This program will print a greeting to the console.  First, open a new text file, and put the following text into it:

	<subroutine name="main">
		global greeting 
		greeting equals "Hello, world!"
		print "Greeting: $greeting"
	</subroutine>

Save this to a file named `helloworld.sim`.  Now, we will compile the code using `sim.pl`;  instead of the default output filename of `out.pl`, we'll use the more appropriate name `helloworld.pl`.  When compilation is done, we'll run our program to see if it works:

	localhost:~ user$ perl sim.pl -o helloworld.pl helloworld.sim
	localhost:~ user$ perl helloworld.pl
	Greeting: Hello, world!
	localhost:~ user$

You can find this program in the `examples/` directory, named `helloworld.sim`.

# SIMPLE Markup Language

**SIMPLE** uses two markup elements:  `subroutine` and `import`.  HTML/XML style multi-line comments (that is, any text between matching tags `<!--` and `-->`) are supported.

`subroutine` elements contain **SIMPLE** Code (see below), and allow blocks of code to be independently executed.  Each `subroutine` element has one mandatory attribute (`name`) and one optional attribute (`arguments`).  The `name` attribute defines what the `subroutine`'s name is;  each `subroutine` name must be unique in the program.  The optional `arguments` attribute sets what arguments the `subroutine` will take.  This is set as a list of names:  one name for each argument, separated by commas.  For example, if you wanted a `subroutine` to take two arguments, the first named `one` and the second named `second`, you would use `arguments="one,second"`.  When executed, a variable is created for each argument containing that argument's value;  these can be used just like any other variable in interpolation.  Thus, in the previous example, the argument one can be referenced with `$one`, the second with `$second`, and so on.  These argument variables are destroyed (that is, removed from the variable table) at the conclusion of the `subroutine`.  Every **SIMPLE** program must contain a `subroutine` named `main`;  this is the "entry point" for the program, and the `subroutine` that is executed by default (this can be changed with the compiler option `-d`).  A subroutine must be defined with a `subroutine` element before it can be used in another subroutine;  that is, like C/C++, the `subroutine` must be written first and before any subroutine that calls it.

`import` elements are used to "import" other **SIMPLE** program files into a program, much like C/C++'s #include.  `import` elements have no attributes;  they contain a single filename, complete with path.  The contents of an imported file are loaded into memory and compiled;  any `subroutine`s they contain may be called by any subsequent subroutines.  Multiple layers of `import` elements are permitted (that is, an imported file can contain `import` elements, which contains more `import` elements, etc.).

# SIMPLE Code Syntax

**SIMPLE** Code is multi-line text with either a blank line or a single **SIMPLE** statement, followed by a newline, on each line.  XML-style multi-line comments can also be used (any code between `<!--` and `-->` will be ignored).

There are 24 built-in SIMPLE commands.  Each one is issued as a series of tokens, separated by whitespace.  If a token contains whitespace in its value, it can be contained in double quotes.  For example, if we were to split the string `this is a test` into tokens, it would split into four (4) tokens:

	Token 1:  this
	Token 2:  is
	Token 3:  a
	Token 4:  test

Now, let's look at a more complicated example, showing how double quotes can be used to contain complete tokens.

	this is "a more complicated" example

	This breaks down into four (4) tokens:

	Token 1:  this
	Token 2:  is
	Token 3:  a more complicated
	Token 4:  example

There are two types of SIMPLE statements:  **commands** and **variable** assignment.  Commands are formatted like so:

╔═══════════════════╦═══╦══════════════╦═════╦═══╗
║      **COMMAND**      ║ [ ║   **ARGUMENT**   ║ ... ║ ] ║
╚═══════════════════╩═══╩══════════════╩═════╩═══╝

adg