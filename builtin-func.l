%top{
// Include cstdint at the start of the generated file. Typically
// MSVC will include this header later, after the definitions of
// the integral type macros. MSVC then complains that about the
// redefinition of the types. Including cstdint early avoids this.
#include <cstdint>
}

%{
#include <ctype.h>
#include <unistd.h>
#include <cstring>
#include <memory>
#include "bif_arg.h"
#include "bif_parse.h"

char* copy_string(const char* s)
	{
	char* c = new char[strlen(s)+1];
	strcpy(c, s);
	return c;
	}

int line_number = 1;

extern bool in_c_code;

int check_c_mode(int t)
	{
	if ( ! in_c_code )
		return t;

	yylval.str = copy_string(yytext);
	return TOK_C_TOKEN;
	}
%}

WS	[ \t]+
OWS	[ \t]*
IDCOMPONENT [A-Za-z_][A-Za-z_0-9]*
ID	{IDCOMPONENT}(::{IDCOMPONENT})*
ESCSEQ	(\\([^\n]|[0-7]+|x[[:xdigit:]]+))
DEC [[:digit:]]+
HEX	[0-9a-fA-F]+


%option nodefault

%%

#.*	{
	yylval.str = copy_string(yytext);
	return TOK_COMMENT;
	}

\n	{
	++line_number;
	return TOK_LF;
	}

{WS}	{
	yylval.str = copy_string(yytext);
	return TOK_WS;
	}

[=,:;]	return check_c_mode(yytext[0]);

"%{"	return TOK_LPB;
"%}"	return TOK_RPB;
"%%{"	return TOK_LPPB;
"%%}"	return TOK_RPPB;

"%("		return check_c_mode(TOK_LPP);
"%)"		return check_c_mode(TOK_RPP);
"..."		return check_c_mode(TOK_VAR_ARG);
"function"	return check_c_mode(TOK_FUNCTION);
"event"		return check_c_mode(TOK_EVENT);
"const"		return check_c_mode(TOK_CONST);
"enum"		return check_c_mode(TOK_ENUM);
"type"		return check_c_mode(TOK_TYPE);
"record"	return check_c_mode(TOK_RECORD);
"set"		return check_c_mode(TOK_SET);
"table"		return check_c_mode(TOK_TABLE);
"vector"	return check_c_mode(TOK_VECTOR);
"of"            return check_c_mode(TOK_OF);
"opaque"        return check_c_mode(TOK_OPAQUE);
"module"        return check_c_mode(TOK_MODULE);

"@ARG@"		return TOK_ARG;
"@ARGS@"	return TOK_ARGS;
"@ARGC@"	return TOK_ARGC;

"T"	yylval.val = 1; return TOK_BOOL;
"F"	yylval.val = 0; return TOK_BOOL;

{DEC}	{
	yylval.str = copy_string(yytext);
	return TOK_INT;
	}

"0x"{HEX} {
	yylval.str = copy_string(yytext);
	return TOK_INT;
	}


{ID}	{
	yylval.str = copy_string(yytext);
	return TOK_ID;
	}

  /*
  Hacky way to pass along arbitrary attribute expressions since the BIF parser
  has little understanding of valid Zeek expressions.  With this pattern, the
  attribute expression should stop when it reaches another attribute, another
  function argument, or the end of the function declaration.
  */
&{ID}({OWS}={OWS}[^&%;,]+)?	{
	int t = check_c_mode(TOK_ATTR);

	if ( t == TOK_ATTR )
		{
		yylval.str = copy_string(yytext);
		return TOK_ATTR;
		}
	else
		return t;
	}

\"([^\\\n\"]|{ESCSEQ})*\"	{
	yylval.str = copy_string(yytext);
	return TOK_CSTR;
	}

\'([^\\\n\']|{ESCSEQ})*\'	{
	yylval.str = copy_string(yytext);
	return TOK_CSTR;
	}

.	{
	yylval.val = yytext[0];
	return TOK_ATOM;
	}
%%

int yywrap()
	{
	yy_delete_buffer(YY_CURRENT_BUFFER);
	return 1;
	}

extern int yyparse();
char* input_filename = nullptr;
char* input_filename_with_path = nullptr;
char* plugin = nullptr;
bool  alternative_mode = false;

FILE* fp_zeek_init = nullptr;
FILE* fp_func_def = nullptr;
FILE* fp_func_h = nullptr;
FILE* fp_func_init = nullptr;
FILE* fp_func_register = nullptr;
FILE* fp_netvar_h = nullptr;
FILE* fp_netvar_def = nullptr;
FILE* fp_netvar_init = nullptr;

void remove_file(const char *surfix);
void err_exit(void);
FILE* open_output_file(const char* surfix);
void close_if_open(FILE **fpp);
void close_all_output_files(void);


FILE* open_output_file(const char* surfix)
	{
	char fn[1024];
	FILE* fp;

	snprintf(fn, sizeof(fn), "%s.%s", input_filename, surfix);
	if ( (fp = fopen(fn, "w")) == NULL )
		{
		fprintf(stderr, "Error: cannot open file: %s\n", fn);
		err_exit();
		}

	return fp;
	}

void usage()
	{
	fprintf(stderr, "usage: bifcl [-p <plugin> | -s] *.bif\n");
	exit(1);
	}

void init_alternative_mode()
	{
	fp_zeek_init = open_output_file("zeek");
	fp_func_h = open_output_file("h");
	fp_func_def = open_output_file("cc");
	fp_func_init = open_output_file("init.cc");
	fp_func_register = plugin ? open_output_file("register.cc") : nullptr;

	fp_netvar_h = fp_func_h;
	fp_netvar_def = fp_func_def;
	fp_netvar_init = fp_func_init;

	int n = 1024 + strlen(input_filename);
	auto auto_gen_comment_buf = std::make_unique<char[]>(n);
	auto auto_gen_comment = auto_gen_comment_buf.get();

	snprintf(auto_gen_comment, n,
		 "This file was automatically generated by bifcl from %s (%s mode).",
		 input_filename_with_path, plugin ? "plugin" : "alternative");

	fprintf(fp_zeek_init, "# %s\n\n", auto_gen_comment);
	fprintf(fp_func_def, "// %s\n\n", auto_gen_comment);
	fprintf(fp_func_h, "// %s\n\n", auto_gen_comment);
	fprintf(fp_func_h, "#pragma once\n\n");
	fprintf(fp_func_init, "// %s\n\n", auto_gen_comment);

	if ( fp_func_register )
		fprintf(fp_func_register, "// %s\n\n", auto_gen_comment);

	static char guard[1024];
	if ( getcwd(guard, sizeof(guard)) == NULL )
		{
		fprintf(stderr, "Error: cannot get current working directory\n");
		err_exit();
		}
	strncat(guard, "/", sizeof(guard) - strlen(guard) - 1);
	strncat(guard, input_filename, sizeof(guard) - strlen(guard) - 1);

	for ( char* p = guard; *p; p++ )
		{
		if ( ! isalnum(*p) )
			*p = '_';
		}

	fprintf(fp_func_h, "#if defined(ZEEK_IN_NETVAR) || ! defined(%s)\n", guard);

	fprintf(fp_func_h, "#ifndef ZEEK_IN_NETVAR\n");
	fprintf(fp_func_h, "#ifndef %s\n", guard);
	fprintf(fp_func_h, "#define %s\n", guard);
	fprintf(fp_func_h, "#include \"zeek/zeek-bif.h\"\n");
	fprintf(fp_func_h, "#endif\n");
	fprintf(fp_func_h, "#endif\n");
	fprintf(fp_func_h, "\n");

	fprintf(fp_func_def, "\n");
	fprintf(fp_func_def, "#include \"%s.h\"\n", input_filename);
	fprintf(fp_func_def, "#include \"zeek/Func.h\"\n");
	fprintf(fp_func_def, "\n");

	static char name[1024];
	strncpy(name, input_filename, sizeof(name) - 1);
	name[sizeof(name) - 1] = '\0';
	char* dot = strchr(name, '.');
	if ( dot )
		*dot = '\0';

	if ( plugin )
		{
		static char plugin_canon[1024];
		strncpy(plugin_canon, plugin, sizeof(plugin_canon) - 1);
		plugin_canon[sizeof(plugin_canon) - 1] = '\0';
		char* colon = strstr(plugin_canon, "::");

		if ( colon ) {
			*colon = '_';
			memmove(colon + 1, colon + 2, plugin_canon + strlen(plugin_canon) - colon);
			}

		fprintf(fp_func_init, "\n");
		fprintf(fp_func_init, "#include <list>\n");
		fprintf(fp_func_init, "#include <string>\n");
		fprintf(fp_func_init, "#include \"zeek/plugin/Plugin.h\"\n");
		fprintf(fp_func_init, "#include \"zeek/Func.h\"\n");
		fprintf(fp_func_init, "#include \"%s.h\"\n", input_filename);
		fprintf(fp_func_init, "\n");
		fprintf(fp_func_init, "namespace plugin::%s {\n", plugin_canon);
		fprintf(fp_func_init, "\n");
		fprintf(fp_func_init, "void __bif_%s_init(zeek::plugin::Plugin* plugin)\n", name);
		fprintf(fp_func_init, "\t{\n");

		fprintf(fp_func_register, "#include \"zeek/plugin/Manager.h\"\n");
		fprintf(fp_func_register, "\n");
		fprintf(fp_func_register, "namespace plugin::%s {\n", plugin_canon);
		fprintf(fp_func_register, "void __bif_%s_init(zeek::plugin::Plugin* plugin);\n", name);
		fprintf(fp_func_register, "zeek::plugin::detail::__RegisterBif __register_bifs_%s_%s(\"%s\", __bif_%s_init);\n", plugin_canon, name, plugin, name);
		fprintf(fp_func_register, "}\n");
        }
	}

void finish_alternative_mode()
	{
	fprintf(fp_func_h, "\n");
	fprintf(fp_func_h, "#endif\n");

	if ( plugin )
		{
		fprintf(fp_func_init, "\n");
		fprintf(fp_func_init, "\t}\n");
		fprintf(fp_func_init, "}\n");
		fprintf(fp_func_init, "\n");
		fprintf(fp_func_init, "\n");
		}
	}

// GCC uses __SANITIZE_ADDRESS__, Clang uses __has_feature
#if defined(__SANITIZE_ADDRESS__)
	#define USING_ASAN
#endif

#if defined(__has_feature)
	#if __has_feature(address_sanitizer)
		#define USING_ASAN
	#endif
#endif

// FreeBSD doesn't support LeakSanitizer
#if defined(USING_ASAN) && !defined(__FreeBSD__)
	#include <sanitizer/lsan_interface.h>
	#define BIFCL_LSAN_DISABLE() __lsan_disable()
#else
	#define BIFCL_LSAN_DISABLE()
#endif

int main(int argc, char* argv[])
	{
	// We generally do not care at all if bifcl is leaking and the default
	// behavior of LSAN to treat leaks as errors only trips up Zeek's build.
	BIFCL_LSAN_DISABLE();

	int opt;

	while ( (opt = getopt(argc, argv, "p:s")) != -1 )
		{
		switch ( opt ) {
		case 'p':
			alternative_mode = true;
			plugin = (char*) optarg;
			break;

		case 's':
			alternative_mode = true;
			break;

		default:
			usage();
		}
		}

	for ( int i = optind; i < argc; i++ )
		{
		FILE* fp_input;

		input_filename = input_filename_with_path = argv[i];
		char* slash = strrchr(input_filename, '/');

		if ( (fp_input = fopen(input_filename, "r")) == NULL )
			{
			fprintf(stderr, "Error: cannot open file: %s\n", input_filename);
			/* no output files open. can simply exit */
			exit(1);
			}

		if ( slash )
			input_filename = slash + 1;

		if ( ! alternative_mode )
			{
			fp_zeek_init = open_output_file("zeek");
			fp_func_h = open_output_file("func_h");
			fp_func_def = open_output_file("func_def");
			fp_func_init = open_output_file("func_init");
			fp_netvar_h = open_output_file("netvar_h");
			fp_netvar_def = open_output_file("netvar_def");
			fp_netvar_init = open_output_file("netvar_init");

			int n = 1024 + strlen(input_filename);
			auto auto_gen_comment_buf = std::make_unique<char[]>(n);
			auto auto_gen_comment = auto_gen_comment_buf.get();

			snprintf(auto_gen_comment, n,
				"This file was automatically generated by bifcl from %s.",
				input_filename);

			fprintf(fp_zeek_init, "# %s\n\n", auto_gen_comment);
			fprintf(fp_func_def, "// %s\n\n", auto_gen_comment);
			fprintf(fp_func_h, "// %s\n\n", auto_gen_comment);
			fprintf(fp_func_h, "#pragma once\n\n");
			fprintf(fp_func_init, "// %s\n\n", auto_gen_comment);
			fprintf(fp_netvar_def, "// %s\n\n", auto_gen_comment);
			fprintf(fp_netvar_h, "// %s\n\n", auto_gen_comment);
			fprintf(fp_netvar_h, "#pragma once\n\n");
			fprintf(fp_netvar_init, "// %s\n\n", auto_gen_comment);
			}

		else
			init_alternative_mode();

		fprintf(fp_netvar_init, "#ifdef __GNUC__\n");
		fprintf(fp_netvar_init, "#pragma GCC diagnostic push\n");
		fprintf(fp_netvar_init, "#pragma GCC diagnostic ignored \"-Wdeprecated-declarations\"\n\n");
		fprintf(fp_netvar_init, "#endif\n");

		yy_switch_to_buffer(yy_create_buffer(fp_input, YY_BUF_SIZE));
		yyparse();

		fprintf(fp_netvar_init, "#ifdef __GNUC__\n");
		fprintf(fp_netvar_init, "\n\n#pragma GCC diagnostic pop\n");
		fprintf(fp_netvar_init, "#endif\n");

		if ( alternative_mode )
			finish_alternative_mode();

		fclose(fp_input);
		close_all_output_files();

		}
	}

void close_if_open(FILE **fpp)
	{
	if (*fpp)
		fclose(*fpp);
	*fpp = nullptr;
	}

void close_all_output_files(void)
	{
	close_if_open(&fp_zeek_init);
	close_if_open(&fp_func_h);
	close_if_open(&fp_func_def);
	close_if_open(&fp_func_init);
	close_if_open(&fp_func_register);

	if ( ! alternative_mode )
		{
		close_if_open(&fp_netvar_h);
		close_if_open(&fp_netvar_def);
		close_if_open(&fp_netvar_init);
		}
	}

void remove_file(const char *surfix)
	{
	char fn[1024];

	snprintf(fn, sizeof(fn), "%s.%s", input_filename, surfix);
	unlink(fn);
	}

void err_exit(void)
	{
	close_all_output_files();
	/* clean up. remove all output files we've generated so far */
	remove_file("zeek");
	remove_file("func_h");
	remove_file("func_def");
	remove_file("func_init");
	remove_file("func_register");
	remove_file("netvar_h");
	remove_file("netvar_def");
	remove_file("netvar_init");
	exit(1);
	}
