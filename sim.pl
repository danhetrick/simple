#!/usr/bin/perl
# 
#  .d8888b. 8888888 888b     d888 8888888b.  888      8888888888 
# d88P  Y88b  888   8888b   d8888 888   Y88b 888      888        
# Y88b.       888   88888b.d88888 888    888 888      888        
#  "Y888b.    888   888Y88888P888 888   d88P 888      8888888    
#     "Y88b.  888   888 Y888P 888 8888888P"  888      888        
#       "888  888   888  Y8P  888 888        888      888        
# Y88b  d88P  888   888   "   888 888        888      888        
#  "Y8888P" 8888888 888       888 888        88888888 8888888888
#
# VERSION 0.00154 (DRAGON)
#
# Simple Interpolated MarkuP LanguagE Compiler
#
# Compiles SIMPLE code to Perl.  All generated Perl code is stand-alone, and requires
# nothing except Perl and the core libraries;  no CPAN modules are used or required.
#
# Copyright (c) 2013, Dan Hetrick
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
#	* Redistributions of source code must retain the above copyright notice, this list of
#	conditions and the following disclaimer.
#	
#	* Redistributions in binary form must reproduce the above copyright notice, this list
#	of conditions and the following disclaimer in the documentation and/or other materials
#   provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
# THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings;

# |----------------------|
# | Core Library Modules |
# |----------------------|

use Text::ParseWords;
use Getopt::Long;

# |--------------------|
# | Local CPAN Modules |
# |--------------------|

use FindBin qw($RealBin);
use lib $RealBin.'/lib';

use XML::TreePP;
use Digest::MD5  qw(md5 md5_hex md5_base64);

# |------------------|
# | Global Constants |
# |------------------|

# structure for the internal subroutine table
use constant SUBROUTINE_NAME      => 0;		# the name of the subroutine
use constant SUBROUTINE_CODE      => 1;		# the compiled subroutine code
use constant SUBROUTINE_ARGUMENTS => 2;		# the subroutine's arguments
use constant SUBROUTINE_ID        => 3;		# the randomly generated subroutine's ID

# |----------------|
# | Global Scalars |
# |----------------|

my $APPLICATION =               'SIMPLE Code Compiler';			# application name
my $VERSION =                   '0.00154';						# application version
my $RELEASE =                   'dragon';						# release codename
my $SIMPLE_EXECUTOR_STUB =      join('',<DATA>);				# executor stub
my $SINGLE_QUOTE_FILTER =       '%__q'.int(rand(100000)).'__%';	# randomly generated single quote symbol
my $OUTPUT_FILE =               'out.pl';						# default output filename
my $ENTRY_POINT =               'main';							# default entry point subroutine
my $SUBROUTINE_TAG =            'subroutine';					# subroutine tag name
my $IMPORT_TAG =                'import';						# import tag name
my $SPLIT_SUB_ARGUMENT_NAME =   'result';						# split function default argument
my $GLOBAL_VARIABLE_COMMAND = 	'global';						# global variable command name
my $LOCAL_VARIABLE_COMMAND = 	'local';						# local variable command name
my $VERBOSE;													# --verbose flag for commandline
my $STRIP_STUB;													# --executor flag for commandline
my $STDOUT;														# --stdout flag for commandline
my $INJECT_CODE;												# --inject flag for commandline

# |---------------|
# | Global Arrays |
# |---------------|

my @ERRORS =            ();		# stores compile-time errors for display
my @SUBROUTINE_TABLE =  ();		# stores subroutine data

# |--------------|
# | Main Program |
# |--------------|

# handle command line options
Getopt::Long::Configure ("bundling");
GetOptions(
	'o|output=s' => \$OUTPUT_FILE,		# sets the output filename
	'd|default=s' => \$ENTRY_POINT,		# sets the default entry point
	'v|verbose' => \$VERBOSE,			# turns on the verbose flag
	'h|help' => sub{ usage(); exit; },	# displays help information
	'e|executor' => \$STRIP_STUB,		# strips the executor stub from output
	's|stdout' => \$STDOUT,				# prints output to stdout
	'i|include' => \$INJECT_CODE,		# injects original source into compiled code
);

# if no filename is passed on the command line, print usage information and exit
if($#ARGV==0){}else{
	usage();
	exit 1;
}

# load input file into memory
if( (-e $ARGV[0]) && (-f $ARGV[0]) ){}else{
	print "File \"$ARGV[0]\" not found.\n";
	exit 1;
}

# insert randomly generated single quote symbol into the execution stub
$SIMPLE_EXECUTOR_STUB=~s/%SINGLE_QUOTE_FILTER%/$SINGLE_QUOTE_FILTER/g;

# insert compiler version and release into the execution stub
$SIMPLE_EXECUTOR_STUB=~s/%VERSION%/$VERSION/g;
$SIMPLE_EXECUTOR_STUB=~s/%RELEASE%/$RELEASE/g;

# using the --stdout option cancels out the --verbose option
if($STDOUT){
	if($VERBOSE){
		$VERBOSE = undef;
	}
}

# display app name and version if in verbose mode
verbose("$APPLICATION $VERSION ($RELEASE)");

# parse all XML in the input file and compile all SIMPLE subroutines
parse_and_compile_SIMPLE_XML_document($ARGV[0]);

# get main subroutine from internal compiled code table
my $COMPILED_MAIN_SUBROUTINE = get_compiled_subroutine_code($ENTRY_POINT)."\n";

# check to make sure the default entry point exists, and exit if not
if(defined $COMPILED_MAIN_SUBROUTINE){
	# inject the default "end of block lable" for function return support
	$COMPILED_MAIN_SUBROUTINE=~s/\%END_BLOCK_LABLE\%/END_BLOCK_MAIN/g;
} else {
	error("Function \"$ENTRY_POINT\" not found!");
}

# all compiled user subroutines are appended to the compiled entry point
foreach my $func (@SUBROUTINE_TABLE) {
	my @function = @{$func};

	# skip the default entry point (it's already been added to the output)
	if($function[SUBROUTINE_NAME] eq $ENTRY_POINT){ next; }

	# generate a unique label id, and inject it into the subroutine's code
	# this provides the functionality for the "return" command
	my $END_LABLE = generate_end_block_id();
	$function[SUBROUTINE_CODE]=~s/\%END_BLOCK_LABLE\%/$END_LABLE/g;

	# append the compiled and processed subroutine
	$COMPILED_MAIN_SUBROUTINE .= "\nsub $function[SUBROUTINE_ID] {\n$function[SUBROUTINE_CODE]\n}\n";
}

# if any syntax errors were found, display them and exit
if(found_syntax_errors()){
	print get_error_display_text()."\n";
	exit 1;
} else {
	verbose("No errors detected!");
}

# print compiled output to STDOUT if the flag is set
if($STDOUT){
	if($STRIP_STUB){
		# print without executor stub
		print $COMPILED_MAIN_SUBROUTINE;
	} else {
		# print with executor stub
		print $SIMPLE_EXECUTOR_STUB.$COMPILED_MAIN_SUBROUTINE;
	}
	exit;
}

# write compiled output to disk
verbose("Writing output to $OUTPUT_FILE");
open(FILE,">$OUTPUT_FILE") or die "Error writing to \"$OUTPUT_FILE\"";
if($STRIP_STUB){
	# write without executor stub
	print FILE $COMPILED_MAIN_SUBROUTINE;
} else {
	# write with executor stub
	print FILE $SIMPLE_EXECUTOR_STUB.$COMPILED_MAIN_SUBROUTINE;
}
close FILE;

# |---------------------|
# | Support Subroutines |
# |---------------------|

# verbose
# usage
# generate_end_block_id
# generate_subroutine_id
# compile_SIMPLE_code_to_perl
# error
# found_syntax_errors
# get_error_display_text
# parse_and_compile_SIMPLE_XML_document
# get_compiled_subroutine_code

# verbose
# Arguments: 1 (scalar)
# Returns: nothing
# Description: Prints the first argument to the console followed by a newline if the
#              verbose flag is tured on.
sub verbose {
	my $text = shift;
	if($VERBOSE){ print $text."\n"; }
}

# usage
# Arguments: none
# Returns: none
# Description: Prints usage information to the console
sub usage {
	print "$APPLICATION $VERSION ($RELEASE)\n";
	print "Usage: $0 [OPTIONS] FILENAME\n";
	print "Options:\n";
	print "-h(elp)				Display this text\n";
	print "-v(erbose)			Displays additional information while compiling\n";
	print "-o(utput) FILENAME		Sets the output filename; default is \"out.pl\"\n";
	print "-d(efault) SUBROUTINE		Sets the default subroutine; default is \"main\"\n";
	print "-e(xecutor)			Strips executor stub from compiled code\n";
	print "-s(tdout)			Prints output to STDOUT instead of a file\n";
	print "-i(nclude)			Includes the original source code into the compiled source\n"
}

# generate_end_block_id
# Arguments: none
# Returns: scalar
# Description: Generates a unique (for the purposes of this program) ID for use
#              in the code block system (used by the "return" command)
sub generate_end_block_id {
	my $HASH = uc(md5_hex(time().'_'.int(rand(1000000)).'_'.int(rand(1000000))));
	my $END_LABLE = 'END_OF_BLOCK_'.$HASH;
	return $END_LABLE;
}

# generate_subroutine_id
# Arguments: none
# Returns: scalar
# Description: Generates a unique (for the purposes of this program) ID for use
#              in the subroutine system
sub generate_subroutine_id {
	my $HASH = uc(md5_hex(time().'_'.int(rand(1000000)).'_'.int(rand(1000000))));
	my $END_LABLE = 'SUBROUTINE_'.$HASH;
	return $END_LABLE;
}

# compile_SIMPLE_code_to_perl
# Arguments: 2 (scalar, scalar)
# Returns: scalar
# Description: Compiles SIMPLE code to Perl.  First argument is the name of the block
#              being compiled, second argument is the SIMPLE code to compile
sub compile_SIMPLE_code_to_perl {
	my $block = shift;
	my $code = shift;
	
	verbose("Compiling $block");
	
	my @compiled = ();		# where we store compiled code
	my $in_while_block = 0;	# keeps track of whether we're in a while block
	my $in_if_block = 0;	# keeps track of whether we're in an if block
	my $line_count = 0;		# keeps track of line count

	# strip leading newlines
	$code=~s/^\n+//;
	
	# convert single quotes into an intermediate symbol
	# this will be converted back to single quotes on interpolation
	$code =~ s/'/$SINGLE_QUOTE_FILTER/g;
	
	# step through each line of the input and convert SIMPLE code to Perl
	foreach my $line (split("\n",$code)) {
	
		# increment line counter
		$line_count += 1;

		# "clean up" line of text
		chomp $line;		# strip trailing linefeed
		$line=~s/^\s+//;	# strip leading whitespace
		$line=~s/\s+$//;	# strip trailing whitespace
		
		# skip blank lines
		if($line eq '') {
			next;
		}

		# inject source code if that flag is turned on
		if($INJECT_CODE){
			push(@compiled,"#  '$block' line $line_count: $line");
		}
		
		# tokenize the line, using spaces as a delimiter
		my @tokens = &quotewords('\s+', 0, $line);
		
		# |-------------------------------|
		# | variable creation and setting |
		# | ------------------------------|

		# global variables
		
		# global NAME
		if( ($#tokens==1) && (lc($tokens[0]) eq $GLOBAL_VARIABLE_COMMAND) ) {
			my $variable_name = $tokens[1];
			push(@compiled,"create_scalar(\"$variable_name\",\"\");");
			next;
		}

		# global NAME equals VALUE
		if( ($#tokens==3) && (lc($tokens[0]) eq $GLOBAL_VARIABLE_COMMAND) && (lc($tokens[2]) eq 'equals') ) {
			my $variable_name = $tokens[1];
			my $variable_value = $tokens[3];
			push(@compiled,"create_scalar(\"$variable_name\",i('$variable_value'));");
			next;
		}
		
		# local variables
		
		# local NAME
		if( ($#tokens==1) && (lc($tokens[0]) eq $LOCAL_VARIABLE_COMMAND) ) {
			my $variable_name = $tokens[1];
			
			push(@compiled,"create_local(\"$variable_name\",\"\");");
			next;
		}

		# local NAME equals VALUE
		if( ($#tokens==3) && (lc($tokens[0]) eq $LOCAL_VARIABLE_COMMAND) && (lc($tokens[2]) eq 'equals') ) {
			my $variable_name = $tokens[1];
			my $variable_value = $tokens[3];
			
			push(@compiled,"create_local(\"$variable_name\",i('$variable_value'));");
			next;
		}

		# variable assignment

		# variable = COMMAND ARG
		my $found_command = 0;
		if( ($#tokens==3) && (lc($tokens[1]) eq 'equals') ) {
			my $variable = $tokens[0];
			my $qvariable = quotemeta($variable);
			my $cmd_name = $tokens[2];
			my $cmd_arg = $tokens[3];
			
			# variable = lowercase STRING
			if(lc($cmd_name eq 'lowercase')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	change_scalar_value(i('$variable'),lc(i('$cmd_arg')));\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}
			
			# variable = uppercase STRING
			if(lc($cmd_name eq 'uppercase')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	change_scalar_value(i('$variable'),uc(i('$cmd_arg')));\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}
			
			# variable = read FILENAME
			if(lc($cmd_name eq 'read')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	\$BUFFER = i('$cmd_arg');\n";
				$c .=  "	open(FILE,\"<\$BUFFER\") or die \"Error reading file '\$BUFFER'\";\n";
				$c .=  "	\$BUFFER = join('',<FILE>);\n";
				$c .=  "	close FILE;\n";
				$c .=  "	change_scalar_value(i('$variable'),\$BUFFER);\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}
			
			# variable = binread FILENAME
			if(lc($cmd_name eq 'binread')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	\$BUFFER = i('$cmd_arg');\n";
				$c .=  "	open(FILE,\"<\$BUFFER\") or die \"Error reading file '\$BUFFER'\";\n";
				$c .=  "	binmode FILE;\n";
				$c .=  "	\$BUFFER = join('',<FILE>);\n";
				$c .=  "	close FILE;\n";
				$c .=  "	change_scalar_value(i('$variable'),\$BUFFER);\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}
			
			# variable = ascii CHARACTER
			if(lc($cmd_name eq 'ascii')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	change_scalar_value(i('$variable'),ord(i('$cmd_arg')));\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}
			
			# variable = character CODE
			if(lc($cmd_name eq 'character')){
				my $c = "if(scalar_exists(i('$variable'))){\n";
				$c .=  "	change_scalar_value(i('$variable'),chr(i('$cmd_arg')));\n";
				$c .=  "} else {\n";
				$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
				$c .=  "	exit 1;\n";
				$c .=  "}";
				push(@compiled,$c);
				$found_command = 1;
			}

		}
		if($found_command==1){ next; }
		

		# VARIABLE = VALUE
		if( ($#tokens==2) && (lc($tokens[1]) eq 'equals') ) {
			my $qvariable = quotemeta($tokens[0]);
			my $c = "if(scalar_exists(i('$tokens[0]'))){\n";
			$c .=  "	change_scalar_value(i('$tokens[0]'),i('$tokens[2]'));\n";
			$c .=  "} else {\n";
			$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
			$c .=  "	exit 1;\n";
			$c .=  "}";
			push(@compiled,$c);
			next;
		}

		# variable = SUBROUTINE [arg...]
		my $found_subroutine = 0;
		if( ($#tokens>=2) && (lc($tokens[1]) eq 'equals') ) {
			my @vwork = @tokens;
			my $variable = shift @vwork;
			my $qvariable = quotemeta($variable);
			shift @vwork;
			my $sub_name = shift @vwork;
			my @sub_args = @vwork;
			my $arg_count = $#sub_args;

			# scan the subroutine table for the desired subroutine
			foreach my $func (@SUBROUTINE_TABLE) {
				my @function = @{$func};
				if($sub_name eq $function[SUBROUTINE_NAME]) {

					# reset the return value
					push(@compiled,"\$RETURN = '';");

					# if there's a discrepancy between the arguments passed to the subroutine
					# and the arguments required by the subroutine, throw an error
					my @args = @{$function[SUBROUTINE_ARGUMENTS]};
					if($#args != $arg_count) {
						error("Error in '$block' on line $line_count:  Wrong number of arguments to \"$function[SUBROUTINE_NAME]\"");
						$found_subroutine = 1;
					}

					# create a local variable for every argument
					my $c = 0;
					foreach my $f (@args) {
						push(@compiled,"create_local('$f',i('$sub_args[$c]'));");
						$c++;
					}

					# insert subroutine call
					push(@compiled,"$function[SUBROUTINE_ID]();");
					
					# handle return value
					$c = "if(scalar_exists(i('$variable'))){\n";
					$c .=  "	change_scalar_value(i('$variable'),\$RETURN);\n";
					$c .=  "} else {\n";
					$c .=  "	print \"Error in '$block' on line $line_count: Variable '$qvariable' doesn't exist.\\n\";\n";
					$c .=  "	exit 1;\n";
					$c .=  "}";
					push(@compiled,$c);
					
					$found_subroutine = 1;
				}
			}
		}
		if($found_subroutine==1){ next; }
		
		# |----------|
		# | commands |
		# |----------|

		# split STRING with DELIMITER to SUBROUTINE
		if( ($#tokens==5) && (lc($tokens[0]) eq 'split') && (lc($tokens[2]) eq 'with') && (lc($tokens[4]) eq 'to') ) {
			my $delimiter = quotemeta($tokens[3]);
			my $string = $tokens[1];
			my $subroutine = $tokens[5];

			# search the subroutine table for the named subroutine
			my $found_sub = 0;
			foreach my $func (@SUBROUTINE_TABLE) {
				my @function = @{$func};
				if($subroutine eq $function[SUBROUTINE_NAME]) {
					$found_sub = 1;

					# get subroutine argument list and check for proper number of arguments
					my @sargs = @{$function[SUBROUTINE_ARGUMENTS]};
					if($#sargs!=0){
						error("Error in '$block' on line $line_count:  Subroutine \"$subroutine\" has the wrong number of arguments");
					} else {
						if($sargs[0] ne $SPLIT_SUB_ARGUMENT_NAME) {
							error("Error in '$block' on line $line_count:  Subroutine \"$subroutine\" doesn't have an argument named \"$SPLIT_SUB_ARGUMENT_NAME\"");
						}

					}

					# generate foreach loop and add it to compiled code
					my $c = "foreach my \$token (split(/$delimiter/,i('$string'))) {\n";
					$c .= "\tcreate_local('$SPLIT_SUB_ARGUMENT_NAME',\$token);\n";
					$c .= "\t$function[SUBROUTINE_ID]();\n";
					$c .= "}";

					push(@compiled,$c);
				}
			}

			if($found_sub==0){
				error("Error in '$block' on line $line_count:  Subroutine \"$subroutine\" doesn't exist");
			}
			next;
		}
		
		# write VALUE to FILENAME
		if( ($#tokens==3) && (lc($tokens[0]) eq 'write' ) && (lc($tokens[2]) eq 'to' ) ) {
			my $filename = $tokens[3];
			my $content = $tokens[1];
			
			my $c = "\$FILENAME = i('$filename');\nopen(FILE,\">\$FILENAME\") or die \"Error writing to '\$FILENAME'\";\n";
			$c .= "print FILE i('$content');\n";
			$c .= "close FILE;";
			
			push(@compiled,$c);
			next;
		}
		
		# append VALUE to FILENAME
		if( ($#tokens==3) && (lc($tokens[0]) eq 'append' ) && (lc($tokens[2]) eq 'to' ) ) {
			my $filename = $tokens[3];
			my $content = $tokens[1];
			
			my $c = "\$FILENAME = i('$filename');\nopen(FILE,\">>\$FILENAME\") or die \"Error writing to '\$FILENAME'\";\n";
			$c .= "print FILE i('$content');\n";
			$c .= "close FILE;";
			
			push(@compiled,$c);
			next;
		}

		# return
		if( ($#tokens==0) && (lc($tokens[0]) eq 'return' ) ) {
			push(@compiled,"\$RETURN = '';");
			push(@compiled,'goto %END_BLOCK_LABLE%;');
			next;
		}
		
		# return VALUE
		if( ($#tokens==1) && (lc($tokens[0]) eq 'return' ) ) {
			my $text = $tokens[1];

			push(@compiled,"\$RETURN = i('$text');");
			push(@compiled,'goto %END_BLOCK_LABLE%;');
			next;
		}
		
		# print TEXT
		if( ($#tokens>=1) && (lc($tokens[0]) eq 'print' ) ) {
			my $text = $tokens[1];
			push(@compiled,"print i('$text').\"\\n\";");
			next;
		}
		
		# prints TEXT
		if( ($#tokens>=1) && (lc($tokens[0]) eq 'prints' ) ) {
			my $text = $tokens[1];
			push(@compiled,"print i('$text');");
			next;
		}
		
		# exit
		if( ($#tokens==0) && ( (lc($tokens[0]) eq 'exit') ) ) {
			push(@compiled,"exit;");
			next;
		}
		
		# exit CODE
		if( ($#tokens==1) && ( (lc($tokens[0]) eq 'exit') ) ) {
			my $ec = $tokens[1];
			
			my $e = "if(is_number(i('$ec'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$ec').\"' is not a number\\n\"; exit 1; }\n";
			$e .= "exit i('$ec');";
		
			push(@compiled,$e);
			next;
		}

		# copy FILENAME to DESTINATION
		if( ($#tokens==3) && (lc($tokens[0]) eq 'copy' ) && (lc($tokens[2]) eq 'to' ) ) {
			my $filename = $tokens[1];
			my $destination = $tokens[3];
			my $c = "if(copy_file(i('$filename'),i('$destination'))){}else{ print \"Error in '$block' on line $line_count: Error copying file '$filename' to '$destination'\\n\"; exit 1; }";
			push(@compiled,$c);
			next;
		}

		# move FILENAME to DESTINATION
		if( ($#tokens==3) && (lc($tokens[0]) eq 'move' ) && (lc($tokens[2]) eq 'to' ) ) {
			my $filename = $tokens[1];
			my $destination = $tokens[3];
			my $c = "if(move_file(i('$filename'),i('$destination'))){}else{ print \"Error in '$block' on line $line_count: Error moving file '$filename' to '$destination'\\n\"; exit 1; }";
			push(@compiled,$c);
			next;
		}

		# delete FILE
		if( ($#tokens==1) && (lc($tokens[0]) eq 'delete' ) ) {
			my $text = $tokens[1];

			my $c = "\$INPUT = i('$text');\n";
			$c .=  "if((-e \$INPUT)&&(-f \$INPUT)){\n";
			$c .=  "	unlink \$INPUT;\n";
			$c .=  "} else {\n";
			$c .=  "	print \"Error in '$block' on line $line_count: File '\$INPUT' doesn't exist.\\n\";\n";
			$c .=  "	exit 1;\n";
			$c .=  "}\n";
			$c .=  "\$INPUT = '';";

			push(@compiled,$c);

			next;
		}

		# input to VARIABLE
		if( ($#tokens==2) && (lc($tokens[0]) eq 'input' ) && (lc($tokens[1]) eq 'to' ) ) {
			my $text = $tokens[2];
			
			my $c = "\$INPUT = <>; chomp(\$INPUT); \n";
			$c .= "if(scalar_exists(i('$text'))){\n";
			$c .=  "	change_scalar_value(i('$text'),\$INPUT);\n";
			$c .=  "} else {\n";
			$c .=  "	print \"Error in '$block' on line $line_count: Variable '$text' doesn't exist.\\n\";\n";
			$c .=  "	exit 1;\n";
			$c .=  "}";

			push(@compiled,$c);

			next;
		}
		
		# |--------------|
		# | flow control |
		# |--------------|
		
		# while LEFT equals|contains RIGHT
		if( ($#tokens==3) && (lc($tokens[0]) eq 'while') ) {
			
			# check for nested while blocks
			if($in_while_block>=1){
				error("Error in '$block' on line $line_count:  Nested while statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition = $tokens[2];
			my $right = $tokens[3];
		
			if( (lc($condition) eq 'equals') || (lc($condition) eq 'is') ) {
				$in_while_block += 1;
				my $w = "while(i('$left') eq i('$right')) {";
				push(@compiled,$w);
				next;
			}

			if( (lc($condition) eq 'has') || (lc($condition) eq 'contains') ) {
				$in_while_block += 1;

				my $w = "\$BUFFER=i('$right');\n";
				$w .= "while(i('$left')=~/\$BUFFER/){";

				push(@compiled,$w);
				next;
			}
		}
		
		# while LEFT is|greater|less not|than RIGHT
		if( ($#tokens==4) && (lc($tokens[0]) eq 'while') ) {
		
			# check for nested while blocks
			if($in_while_block>=1){
				error("Error in '$block' on line $line_count:  Nested while statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition1 = $tokens[2];
			my $condition2 = $tokens[3];
			my $right = $tokens[4];
			
			if( (lc($condition1) eq 'is') && (lc($condition2) eq 'not') ) {
				$in_while_block += 1;
				my $w = "while(i('$left') ne i('$right')) {";
				push(@compiled,$w);
				next;
			}
			
			if( (lc($condition1) eq 'greater') && (lc($condition2) eq 'than') ) {
				
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "while(i('$left') > i('$right')) {";
				
				$in_while_block += 1;
				
				push(@compiled,$w);
				next;
			}
			
			if( (lc($condition1) eq 'less') && (lc($condition2) eq 'than') ) {
				
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "while(i('$left') < i('$right')) {";
				
				$in_while_block += 1;
				push(@compiled,$w);
				next;
			}
		}
		
		# while LEFT less|greater than or equals RIGHT
		if( ($#tokens==6) && (lc($tokens[0]) eq 'while') ) {
		
			# check for nested while blocks
			if($in_while_block>=1){
				error("Error in '$block' on line $line_count:  Nested while statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition1 = $tokens[2];
			my $condition2 = $tokens[3];
			my $condition3 = $tokens[4];
			my $condition4 = $tokens[5];
			my $right = $tokens[6];
		
			if( (lc($condition1) eq 'less') && (lc($condition2) eq 'than') && (lc($condition3) eq 'or') && (lc($condition4) eq 'equals') ) {
			
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "while(i('$left') <= i('$right')) {";
				
				$in_while_block += 1;
				push(@compiled,$w);
				next;
			
			}
			
			if( (lc($condition1) eq 'greater') && (lc($condition2) eq 'than') && (lc($condition3) eq 'or') && (lc($condition4) eq 'equals') ) {
			
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "while(i('$left') >= i('$right')) {";
				
				$in_while_block += 1;
				push(@compiled,$w);
				next;
			
			}
		
		}

		# if LEFT exists
		if( ($#tokens==2) && (lc($tokens[0]) eq 'if') ) {
		
			# check for nested if blocks
			if($in_if_block>=1){
				error("Error in '$block' on line $line_count:  Nested if statements are not allowed");
			}
			
			my $left = $tokens[1];
			my $condition = $tokens[2];
			
			if( (lc($condition) eq 'exists') ) {
				$in_if_block += 1;
				my $w = "if(scalar_exists(i('$left'))){";
				push(@compiled,$w);
				next;
			}
		
		}

		# if LEFT equals|contains RIGHT
		if( ($#tokens==3) && (lc($tokens[0]) eq 'if') ) {
		
			# check for nested if blocks
			if($in_if_block>=1){
				error("Error in '$block' on line $line_count:  Nested if statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition = $tokens[2];
			my $right = $tokens[3];
		
			if( (lc($condition) eq 'equals') || (lc($condition) eq 'is') ) {
				$in_if_block += 1;
				my $w = "if(i('$left') eq i('$right')){";
				push(@compiled,$w);
				next;
			}

			if( (lc($condition) eq 'has') || (lc($condition) eq 'contains') ) {
				$in_if_block += 1;

				my $w = "\$BUFFER=i('$right');\n";
				$w .= "if(i('$left')=~/\$BUFFER/){";

				push(@compiled,$w);
				next;
			}
			
		}
		
		# if LEFT is|greater|less|does not|than RIGHT|exist
		if( ($#tokens==4) && (lc($tokens[0]) eq 'if') ) {
		
			# check for nested if blocks
			if($in_if_block>=1){
				error("Error in '$block' on line $line_count:  Nested if statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition1 = $tokens[2];
			my $condition2 = $tokens[3];
			my $right = $tokens[4];

			if( (lc($condition1) eq 'is') && (lc($condition2) eq 'a') && (lc($right) eq 'number') ) {
				$in_if_block += 1;
				my $w = "if(is_number(i('$left'))){";
				push(@compiled,$w);
				next;
			}

			if( (lc($condition1) eq 'is') && (lc($condition2) eq 'a') && (lc($right) eq 'string') ) {
				$in_if_block += 1;
				my $w = "if(!is_number(i('$left'))){";
				push(@compiled,$w);
				next;
			}

			if( (lc($condition1) eq 'is') && (lc($condition2) eq 'not') ) {
				$in_if_block += 1;
				my $w = "if(i('$left') ne i('$right')){";
				push(@compiled,$w);
				next;
			}
			
			if( (lc($condition1) eq 'greater') && (lc($condition2) eq 'than') ) {
				
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(i('$left') > i('$right')) {";
				
				$in_if_block += 1;
				
				push(@compiled,$w);
				next;
			}
			
			if( (lc($condition1) eq 'less') && (lc($condition2) eq 'than') ) {
				
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(i('$left') < i('$right')) {";
				
				$in_if_block += 1;
				push(@compiled,$w);
				next;
			}
			
			
			
			if( (lc($condition1) eq 'does') && (lc($condition2) eq 'not') && (lc($right) eq 'exist') ) {
				$in_if_block += 1;
				my $w = "if(scalar_exists(i('$left'))) {}else{";
				push(@compiled,$w);
				next;
			}
			
			
		}
		
		# if LEFT less|greater than or equals RIGHT
		if( ($#tokens==6) && (lc($tokens[0]) eq 'if') ) {
		
			# check for nested if blocks
			if($in_if_block>=1){
				error("Error in '$block' on line $line_count:  Nested if statements are not allowed");
			}
		
			my $left = $tokens[1];
			my $condition1 = $tokens[2];
			my $condition2 = $tokens[3];
			my $condition3 = $tokens[4];
			my $condition4 = $tokens[5];
			my $right = $tokens[6];
		
			if( (lc($condition1) eq 'less') && (lc($condition2) eq 'than') && (lc($condition3) eq 'or') && (lc($condition4) eq 'equals') ) {
			
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(i('$left') <= i('$right')) {";
				
				$in_if_block += 1;
				push(@compiled,$w);
				next;
			
			}
			
			if( (lc($condition1) eq 'greater') && (lc($condition2) eq 'than') && (lc($condition3) eq 'or') && (lc($condition4) eq 'equals') ) {
			
				my $w .= "if(is_number(i('$left'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$left').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(is_number(i('$right'))){}else{ print \"Error in '$block' on line $line_count: '\".i('$right').\"' is not a number\\n\"; exit 1; }\n";
				$w .= "if(i('$left') >= i('$right')) {";
				
				$in_if_block += 1;
				push(@compiled,$w);
				next;
			
			}
		
		}
		
		# else
		if( ($#tokens==0) && ( (lc($tokens[0]) eq 'else') ) ) {
		
			# check to make sure we're in an if block
			if($in_if_block<1){
				error("Error in '$block' on line $line_count: Not currently in an if statement");
			}
		
			push(@compiled,"} else {");
			next;
		}
		
		# end
		if( ($#tokens==0) && ( (lc($tokens[0]) eq 'end') ) ) {
		
			# check to make sure we're in an if block
			if($in_if_block<1){
				error("Error in '$block' on line $line_count: Not currently in an if statement");
			}
		
			$in_if_block -= 1;
			push(@compiled,"}");
			next;
		}

		# break
		if( ($#tokens==0) && ( (lc($tokens[0]) eq 'break') ) ) {
		
			# check to make sure we're in a while block
			if($in_while_block<1){
				error("Error in '$block' on line $line_count: Not currently in a while statement");
			}
		
			$in_while_block -= 1;
			push(@compiled,"}");
			next;
		}
		
		
		# user-created subroutines	
		my $found_function = 0;
		foreach my $func (@SUBROUTINE_TABLE) {
			my @function = @{$func};
			if($#tokens>=0){
				if($tokens[0] eq $function[SUBROUTINE_NAME]) {
				
					my $func_code = $function[SUBROUTINE_CODE];
					my @func_args = @{$function[SUBROUTINE_ARGUMENTS]};
					my $argcount = $#tokens-1;

					# if there's a discrepancy between the arguments passed to the subroutine
					# and the arguments required by the subroutine, throw an error
					if($#func_args != $argcount){
						error("Error in '$block' on line $line_count:  Wrong number of arguments to \"$function[SUBROUTINE_NAME]\"");
						$found_function = 1;
					}
					
					# reset the return value, just in case
					push(@compiled,"\$RETURN = '';");
					
					# create a new local variable for every argument
					shift @tokens;
					my $c = 0;
					foreach my $f (@func_args) {
						push(@compiled,"create_local('$f',i('$tokens[$c]'));");
						$c++;
					}

					# insert subroutine call
					push(@compiled,"$function[SUBROUTINE_ID]();");
					
					$found_function = 1;
				}
			}
		}
		if($found_function==1){ next; }

		# command not recognized
		error("Error in '$block' on line $line_count:  Statement \"$line\" not recognized");
	
	}
	
	#  we're still in a while block, throw an error
	if($in_while_block!=0){
		error("Error in '$block':  \"while\" statement missing \"break\"");
	}
	
	# we're still in an if block, throw an error
	if($in_if_block!=0){
		error("Error in '$block':  \"if\" statement missing \"end\"");
	}

	# add the exit block lable, for return() support
	push(@compiled,'%END_BLOCK_LABLE%:');

	# delete all local scalars
	push(@compiled,"destroy_locals();");

	# add newlines in between all code entries
	$code = join("\n",@compiled);
	
	# return compiled code
	return $code;
}

# error
# Arguments: 1 (scalar)
# Returns: nothing
# Description:  Adds an error to the internal error list
sub error {
	my $err = shift;
	push(@ERRORS,$err);
}

# found_syntax_errors
# Arguments: none
# Returns: 1 if there are errors in the internal error list, undef otherwise
# Description: Tests to see if there are errors in the internal error list
sub found_syntax_errors {
	if($#ERRORS>=0){ return 1; } else { return undef; }
}

# get_error_display_text
# Arguments: none
# Returns: scalar
# Description: Builds a "pretty" list of errors from the internal error list
#              for display, and returns it
sub get_error_display_text {
	my $err_count = ($#ERRORS+1);
	
	my $text = "";
	if($err_count==1){
		$text = "1 error found!\n";
	} else {
		$text = "$err_count errors found!\n";
	}
	
	$text .= join("\n",@ERRORS);
	return $text;
}

# get_compiled_subroutine_code
# Arguments: 1 (subroutine name)
# Returns: code if subroutine exists, undef if not
# Description: Gets any compiled subroutine code from the subroutine table
sub get_compiled_subroutine_code {
	my $function_name = shift;
	foreach my $func (@SUBROUTINE_TABLE) {
		my @function = @{$func};
		if($function_name eq $function[SUBROUTINE_NAME]) {
			return $function[SUBROUTINE_CODE];
		}
	}
	return undef;
}

# subroutine_exists
# Arguments: 1 (subroutine name)
# Returns: 1 if subroutine exists, undef if not
# Description: Tests to see if a subroutine exists in the subroutine table
sub subroutine_exists {
	my $function_name = shift;
	foreach my $func (@SUBROUTINE_TABLE) {
		my @function = @{$func};
		if($function_name eq $function[SUBROUTINE_NAME]) {
			return 1;
		}
	}
	return undef;
}

# parse_and_compile_SIMPLE_XML_document
# Arguments: 1 (filename)
# Returns: nothing
# Description: Parses a SIMPLE XML document into memory, compiling all functions
#              found and saving them to the subroutine table
sub parse_and_compile_SIMPLE_XML_document {
	my $file = shift;
	
	my $tpp = XML::TreePP->new();
	$tpp->set( text_node_key => '-source' );
	$tpp->set( force_array => '*' );
	
	my $tree;
	
	if((-e $file)&&(-f $file)){
		open(FILE,"<$file") or die "Error opening \"$file\"";
		verbose("Parsing SIMPLE XML in file $file");
		$file = join('',<FILE>);
		close FILE;
		$tree = $tpp->parse( $file );
	} else {
		error("File \"$file\" not found");
	}
	
	# <import>FILE</import>
	if($tree->{$IMPORT_TAG}){
		foreach my $entry (@{$tree->{$IMPORT_TAG}}) {
			verbose("Importing SIMPLE XML in file $entry");
			$entry=~s/^\n+//;	# strip leading linefeed
			chomp $entry;		# strip trailing linefeed
			$entry=~s/^\s+//;	# strip leading whitespace
			$entry=~s/\s+$//;	# strip trailing whitespace
			parse_and_compile_SIMPLE_XML_document($entry);
		}
		
	}
	
	# <subroutine name="EXAMPLE" arguments="OPTIONAL">CODE</subroutine>
	if($tree->{$SUBROUTINE_TAG}){
		foreach my $entry (@{$tree->{$SUBROUTINE_TAG}}) {
		
			if(defined $entry->{-name}){}else {
				error("XML subroutine is missing a name attribute");
			}
			
			my $SUBROUTINE_NAME = $entry->{-name};
			
			if(subroutine_exists($SUBROUTINE_NAME)){
				error("XML subroutine \"$SUBROUTINE_NAME\" is defined more than once");
			}
			
			if(defined $entry->{-source}){}else {
				error("XML subroutine \"$SUBROUTINE_NAME\" contains no code");
			}
			
			my $SUBROUTINE_CODE = $entry->{-source};
			
			my @ARGUMENTS = ();
			
			if(defined $entry->{-arguments}){
				@ARGUMENTS =  split(",",$entry->{-arguments});
			}

			my $SUBROUTINE_ID = generate_subroutine_id();
			
			verbose("Compiling subroutine \"$SUBROUTINE_NAME\"");
			
			$SUBROUTINE_CODE = compile_SIMPLE_code_to_perl($SUBROUTINE_NAME,$SUBROUTINE_CODE);
			
			my @func = ( $SUBROUTINE_NAME, $SUBROUTINE_CODE, \@ARGUMENTS, $SUBROUTINE_ID );
			push(@SUBROUTINE_TABLE,\@func);
			
		}
	}
	
}

__DATA__
#!/usr/bin/perl
#
# SIMPLE Compiler v%VERSION% (%RELEASE%)
# This program is the output of a compiler.
# Please do not edit it.
#
# |==========================================================================================|
# |                                                                                          |
# |               .d8888b. 8888888 888b     d888 8888888b.  888      8888888888              | 
# |              d88P  Y88b  888   8888b   d8888 888   Y88b 888      888                     |
# |              Y88b.       888   88888b.d88888 888    888 888      888                     |
# |               "Y888b.    888   888Y88888P888 888   d88P 888      8888888                 |
# |                  "Y88b.  888   888 Y888P 888 8888888P"  888      888                     |
# |                    "888  888   888  Y8P  888 888        888      888                     |
# |              Y88b  d88P  888   888   "   888 888        888      888                     |
# |               "Y8888P" 8888888 888       888 888        88888888 8888888888              |
# |                                                                                          |
# |                                   SIMPLE EXECUTOR STUB                                   |
# |                              Copyright (c) 2013, Dan Hetrick                             |
# |                                    All rights reserved.                                  |
# |                                                                                          |
# | Redistribution and use in source and binary forms, with or without modification, are     |
# | permitted provided that the following conditions are met:                                |
# |                                                                                          |
# |	* Redistributions of source code must retain the above copyright notice, this list of    |
# |	conditions and the following disclaimer.                                                 |
# |	                                                                                         |
# |	* Redistributions in binary form must reproduce the above copyright notice, this list    |
# |	of conditions and the following disclaimer in the documentation and/or other materials   |
# | provided with the distribution.                                                          |
# |                                                                                          |
# | THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY      |
# | EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF  |
# | MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL   |
# | THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,     |
# | SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT |
# | OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS              |
# | INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT |
# | LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE |
# | OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                     |
# |                                                                                          |
# | NOTE: ONLY THE EXECUTOR STUB IS LICENSED BY THE ABOVE LICENSE!  ANY COMPILED CODE USES   |
# |       WHATEVER LICENSE THE AUTHOR CHOOSES TO USE.                                        |
# |                                                                                          |
# |                                  BEGIN BSD LICENSED CODE                                 |
# |==========================================================================================|

use strict;
use warnings;

use File::Copy;

# |==========================================================================================|
# |                           BEGIN MATH PARSER CODE BY BART LATEUR                          |
# |==========================================================================================|

# Code mostly from an article by Bart Lateur:
# http://www.perlmonks.org/?node_id=554516

my %op = (
	'+'  => { prec => 10, assoc => 'L', exec => sub { $_[0] + $_[1] }},
	'-'  => { prec => 10, assoc => 'L', exec => sub { $_[0] - $_[1] }},
	'*'  => { prec => 20, assoc => 'L', exec => sub { $_[0] * $_[1] }},
	'/'  => { prec => 20, assoc => 'L', exec => sub { $_[0] / $_[1] }},
	'%'  => { prec => 20, assoc => 'L', exec => sub { $_[0] % $_[1] }},
	'**' => { prec => 30, assoc => 'R', exec => sub { $_[0] ** $_[1] }},
);

use constant VALUE => 0;
use constant OP => 1;

sub do_math {
	my $statement = shift;
	my $x = parse_and_solve_math_statement($statement);
	if(defined $x) { return $x; } else { return $statement; }
}

sub parse_and_solve_math_statement {
    local $_ = shift;
    my $value = math_engine_mpe();
    /\G\s+/gc;
    /\G$/gc or return undef;
    return $value;
}

sub math_engine_mpe {
    my @stack;
    while (1) {
        my($value) = math_engine_mpv() or return 0;
        if(/\G\s*(\*\*|[+\-*\/%\\])/gc) {  # operator
            my $op = $1;
            while (@stack and (($op{$op}{prec} < $op{$stack[-1][OP]}{prec})
              or ($op{$op}{prec} == $op{$stack[-1][OP]}{prec})
               and $op{$stack[-1][OP]}{assoc} eq "L")) {
                my($lhs, $op) = @{pop @stack};
                $value = $op{$op}{exec}->($lhs, $value);
            }
            push @stack, [ $value, $op ];
        } else {  # no more
            while(@stack) {
                my($lhs, $op) = @{pop @stack};
                $value = $op{$op}{exec}->($lhs, $value);
            }
            return $value;
        }
    }
}

sub math_engine_mpv {
    /\G\s+/gc;
    if(/\G\+/gc) {  #  '+' value
        return math_engine_mpv();
    }
    if(/\G-/gc) {  #  '-' value
        return -math_engine_mpv();
    }

    if(/\G((?:\d+\.?\d*|\.\d+)(?i:E[+-]?\d+)?)/gc) {  # number
        return $1;
    }
    if(/\G\(/gc) {  #  '(' expr ')'
        my $value = math_engine_mpe();
        /\G\s*/gc;
        /\G\)/gc or return 0;
        return $value;
    }
    return;
}

# |==========================================================================================|
# |                            END MATH PARSER CODE BY BART LATEUR                           |
# |==========================================================================================|

# |------------------|
# | Global Constants |
# |------------------|

use constant SCALAR_NAME => 0;
use constant SCALAR_VALUE => 1;
use constant SCALAR_DEREFERENCE_SYMBOL => '$';

# |----------------|
# | Global Scalars |
# |----------------|

my $SINGLE_QUOTE_FILTER = '%SINGLE_QUOTE_FILTER%';
my $RETURN = '';
my $BUFFER = '';
my $FILENAME = '';
my $INPUT = '';

# |---------------|
# | Global Arrays |
# |---------------|

my @SCALAR_TABLE = ();
my @LOCAL_TABLE = ();

# |---------------------|
# | Support Subroutines |
# |---------------------|

# i
# Arguments: 1 (string)
# Returns:  scalar (string)
# Description:  Interpolates a string with data from the local and
#               global variable tables.  Local variables are given
#               precedence over global variables (that is, local
#               variables are interpolated first).  If, after all
#               variable interpolation is complete, the string consists
#               of a math statement, the statement is calculated (solved)
#               and the result is returned, rather than the interpolated string.
sub i {
	my $input = shift;
	
	$input=~s/$SINGLE_QUOTE_FILTER/'/;
	
	foreach my $s (@LOCAL_TABLE) {
		my @scalar = @{$s};
		my $tag = quotemeta(SCALAR_DEREFERENCE_SYMBOL.$scalar[SCALAR_NAME]);
		$input=~s/$tag/$scalar[SCALAR_VALUE]/g;
	}
	
	foreach my $s (@SCALAR_TABLE) {
		my @scalar = @{$s};
		my $tag = quotemeta(SCALAR_DEREFERENCE_SYMBOL.$scalar[SCALAR_NAME]);
		$input=~s/$tag/$scalar[SCALAR_VALUE]/g;
	}
	
	$input = do_math($input);
	
	return $input;
}

# is_number
# Arguments: 1 (string)
# Returns:  1 if input is numerical, undef if not.
# Description:  Checks to see if a given piece of data is a number or not.
sub is_number {
	my $data = shift;
	
	if($data=~/\d/){ return 1; } else { return undef; }
}

# change_scalar_value
# Arguments: 2 (scalar name, scalar value)
# Returns:  nothing
# Description:  Changes a scalar value in the local and global variable tables.
#               Local variables take precedence over global variables (that is,
#               if there are identically named variables in both tables, only the
#               local variable will be changed).
sub change_scalar_value {
	my $name = shift;
	my $value = shift;
	
	my $found_local = 0;
	my @NEW_LOCAL_TABLE = ();
	foreach my $s (@LOCAL_TABLE) {
		my @local = @{$s};
		if($local[SCALAR_NAME] eq $name) {
			$local[SCALAR_VALUE] = $value;
			push(@NEW_LOCAL_TABLE,\@local);
			$found_local = 1;
		} else {
			push(@NEW_LOCAL_TABLE,$s);
		}
	}
	
	if($found_local==1){ @LOCAL_TABLE = @NEW_LOCAL_TABLE; return; }
	
	my @NEW_SCALAR_TABLE = ();
	foreach my $s (@SCALAR_TABLE) {
		my @scalar = @{$s};
		if($scalar[SCALAR_NAME] eq $name) {
			$scalar[SCALAR_VALUE] = $value;
			push(@NEW_SCALAR_TABLE,\@scalar);
		} else {
			push(@NEW_SCALAR_TABLE,$s);
		}
	}
	
	@SCALAR_TABLE = @NEW_SCALAR_TABLE;
	
}

# delete_scalar
# Arguments: 1 (scalar name)
# Returns:  nothing
# Description:  Deletes a scalar in the local and global variable tables.
#               Local variables take precedence over global variables (that is,
#               if there are identically named variables in both tables, only the
#               local variable will be deleted).
sub delete_scalar {
	my $name = shift;
	
	my $found_local = 0;
	my @NEW_LOCAL_TABLE = ();
	foreach my $s (@LOCAL_TABLE) {
		my @local = @{$s};
		if($local[SCALAR_NAME] eq $name) {
			next;
			$found_local = 1;
		} else {
			push(@NEW_LOCAL_TABLE,$s);
		}
	}
	
	if($found_local==1){ @LOCAL_TABLE = @NEW_LOCAL_TABLE; return; }
	
	my @NEW_SCALAR_TABLE = ();
	foreach my $s (@SCALAR_TABLE) {
		my @scalar = @{$s};
		if($scalar[SCALAR_NAME] eq $name) {
			next;
		} else {
			push(@NEW_SCALAR_TABLE,$s);
		}
	}
	
	@SCALAR_TABLE = @NEW_SCALAR_TABLE;
	
}

# scalar_exists
# Arguments: 1 (scalar name)
# Returns:  1 if the named scalar exists, undef otherwise
# Description:  Checks to see if a scalar exists.
sub scalar_exists {
	my $name = shift;
	
	foreach my $s (@LOCAL_TABLE) {
		my @scalar = @{$s};
		if($scalar[SCALAR_NAME] eq $name) { return 1; }
	}
	
	foreach my $s (@SCALAR_TABLE) {
		my @scalar = @{$s};
		if($scalar[SCALAR_NAME] eq $name) { return 1; }
	}
	
	return undef;
}

# create_scalar
# Arguments: 2 (scalar name, scalar value)
# Returns:  nothing
# Description:  Creates a new global variable and adds it to the global table.
#               If a variable of the same name already exists, update its value.
sub create_scalar {
	my $name = shift;
	my $value = shift;
	
	if(scalar_exists($name)){
		change_scalar_value($name,$value);
		return;
	}
	
	my @entry = ($name,$value);
	push(@SCALAR_TABLE,\@entry);
	
}

# change_local_value
# Arguments: 2 (scalar name, scalar value)
# Returns:  nothing
# Description:  Changes a local variable's value.
sub change_local_value {
	my $name = shift;
	my $value = shift;
	
	my @NEW_LOCAL_TABLE = ();
	foreach my $s (@LOCAL_TABLE) {
		my @local = @{$s};
		if($local[SCALAR_NAME] eq $name) {
			$local[SCALAR_VALUE] = $value;
			push(@NEW_LOCAL_TABLE,\@local);
		} else {
			push(@NEW_LOCAL_TABLE,$s);
		}
	}
	
	@LOCAL_TABLE = @NEW_LOCAL_TABLE;
	
}

# local_exists
# Arguments: 1 (scalar name)
# Returns:  1 if the named local scalar exists, undef otherwise
# Description:  Checks to see if a local variable exists.
sub local_exists {
	my $name = shift;
	
	foreach my $s (@LOCAL_TABLE) {
		my @local = @{$s};
		if($local[SCALAR_NAME] eq $name) { return 1; }
	}
	
	return undef;
}

# destroy_locals
# Arguments: 0
# Returns:  nothing
# Description:  Clears the local variable table, destroying all local variables.
sub destroy_locals {
	@LOCAL_TABLE = ();
}

# create_local
# Arguments: 2 (scalar name, scalar value)
# Returns:  nothing
# Description:  Creates a new local variable and adds it to the local table.
#               If a variable of the same name already exists, update its value.
sub create_local {
	my $name = shift;
	my $value = shift;
	
	if(local_exists($name)){
		change_local_value($name,$value);
		return;
	}
	
	my @entry = ($name,$value);
	push(@LOCAL_TABLE,\@entry);
	
}

# copy_file
# Arguments: 2 (filename,filename)
# Returns:  1 if successful, undef if not successful
# Description:  Copies a file.
sub copy_file {
	my $file = shift;
	my $destination = shift;

	copy("$file","$destination") or return undef;
	return 1;
}

# move_file
# Arguments: 2 (filename,filename)
# Returns:  1 if successful, undef if not successful
# Description:  Moves a file.
sub move_file {
	my $file = shift;
	my $destination = shift;

	move("$file","$destination") or return undef;
	return 1;
}

# Handle command line interface and create built-in variables
my $counter = 0;
create_scalar("ARGC",($#ARGV+1));
create_scalar("ARGV$counter",$0);
foreach my $arg (@ARGV) {
	$counter += 1;
	create_scalar("ARGV$counter",$arg);
}

# |==========================================================================================|
# |                                  END SIMPLE EXECUTOR STUB                                |
# |==========================================================================================|

# |==========================================================================================|
# |                                   END BSD LICENSED CODE                                  |
# |==========================================================================================|

# |==========================================================================================|
# |                                    BEGIN COMPILED CODE                                   |
# |                    All code after this point is licenced by its author                   |
# |                         and is not covered by the above license.                         |
# |==========================================================================================|

