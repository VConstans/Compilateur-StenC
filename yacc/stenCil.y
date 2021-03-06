%{
  #include <stdio.h>
  #include <stdlib.h>
  #include "enum.h"
  #include "tds.h"
  #include "quads.h"
  #include "list_quads.h"
  #include "tradCode.h"
  #include "dim.h"
  #include "listNumber.h"
  #include "stencil.h"
  #include "util.h"

  void yyerror(char*);
  int yylex();
  void lex_free();

  struct symbol* tds = NULL;
  struct quads* quadsFinal = NULL;

  int nextquad = 1;

  int debug = 0;

%}

%union{
	char* string;
	int value;

	struct{
		struct symbol* result;
		struct quads* code;
		union {
			struct {
				struct list_quads* truelist;
				struct list_quads* falselist;
			};
			struct {
				int nb_dim;
				struct symbol* decal;
			};
		};
	} codegen;

	struct{
		int width;
		struct listNumber* list_number;
		struct dim* list_dim;
		int nb_dim;
	} tab;
}


%token <string>IDENTIFIER
%token <value>NUMBER
%token <value>TRUE
%token <value>FALSE
%token <tab>STENC
%token IF
%token ELSE
%token WHILE
%token FOR
%token RETURN
%token CONST
%token <value>TYPE
%token MAIN
%token PRINTF
%token PRINTI
%token EQUAL
%token LOWEREQ
%token GREATEREQ
%token NOTEQUAL
%token AND
%token OR
%token INCR
%token DECR
%token DIM_SEPARATOR
%token <string>STRING
%token PREPROC

%type <codegen>condition
%type <codegen>expression
%type <codegen>code_line
%type <codegen>statement
%type <codegen>line
%type <codegen>attribution
%type <codegen>declaration
%type <codegen>var
%type <codegen>list_var
%type <codegen>bloc
%type <codegen>avancement_for
%type <value>tag
%type <value>tag_else
%type <tab>array
%type <tab>list_array 
%type <tab>list_number
%type <codegen>variable_attribution
%type <codegen>index_attribution
%type <codegen>index_declaration
%type <codegen>variable_declaration
%type <codegen>variable
%type <codegen>main
%type <codegen>preproc
%type <codegen>list_preproc

%left DIM_SEPARATOR
%left '(' ')'
%left '!' INCR DECR
%left '*' '/' '$'
%left '-' '+' 
%left '<' '>' LOWEREQ GREATEREQ
%left EQUAL NOTEQUAL
%left AND
%left OR
%right '=' 

%start axiom

%%

axiom:
  list_preproc
    {
      quadsFinal = $1.code;
      printf("Match :-) !\n");
      return 0;
    }
;


list_preproc:
  preproc list_preproc
  {
    $$.code = quadsConcat($1.code,$2.code,NULL);

    if(debug)
    {
      printf("list_preproc -> preproc list_preproc\n");
    }
  }

  | main
  {
    $$ = $1;

    if(debug)
    {
      printf("list_preproc -> main\n");
    }
  }
;

preproc:
  PREPROC IDENTIFIER NUMBER
  {
    struct symbol* tmp = lookup(tds,$2);
    if(tmp != NULL)
    {
      printf("ERROR ! Redéclaration de %s\n",$2);
      free_all();
      lex_free();
      exit(-1);
    }
    //Add a new symbol to the table of symbols
    $$.result = add(&tds,$2,true);
    $$.result->type = INT_TYPE;
    $$.result->is_array = false;
    $$.result->value = $3;
    $$.code = NULL;

    if(debug)
    {
      printf("preproc -> ID NUMBER (%d)\n",$3);
    }
  }

main:
  TYPE MAIN '(' ')' bloc
  {
    if($1 != INT_TYPE)
    {
      printf("ERROR ! main() n'a pas de type int\n");
      free_all();
      lex_free();
      exit(-1);
    }

    $$=$5;

    if(debug)
    {
      printf("main -> TYPE MAIN ( ) bloc\n");
    }
  }


bloc:
  '{' line '}'
  {
    $$ = $2;

    if(debug)
    {
      printf("bloc -> { line }\n");
    }
  }
;


line:
  line statement
  {
    $$.code = quadsConcat($1.code,$2.code,NULL);

    if(debug)
    {
      printf("line -> line statement\n");
    }
  }

  | statement
  {
    $$ = $1;

    if(debug)
    {
      printf("line -> statement\n");
    }
  }
;


statement:
  code_line ';'
  {
    $$=$1;

    if(debug)
    {
      printf("statement -> code_line ;\n");
    }
  }

  | WHILE tag condition tag bloc
  {
    //Begin

    //Concaténation de la truelist de la condition
    struct symbol* tmp = newLabel(&tds,$4);
    complete_list_quads($3.truelist, tmp);

    //Ajout du goto begin
    tmp = newLabel(&tds,$2);
    struct quads* newQuads = quadsGen("j", NULL, NULL, tmp);
    $$.code = quadsConcat($3.code,$5.code ,newQuads);

    //Concaténation de la falselist de la condition
    tmp = newLabel(&tds,nextquad);
    complete_list_quads($3.falselist, tmp);

    free_list_quad($3.falselist);
    free_list_quad($3.truelist);

    if(debug)
    {
      printf("statement -> WHILE tag condition tag bloc\n");
    }
  }

  | IF condition tag bloc
  {
    //Concaténation de la truelist de la condition
    struct symbol* tmp = newLabel(&tds,$3);
    complete_list_quads($2.truelist, tmp);

    //Concaténation du code de bloc
    $$.code = quadsConcat($2.code,$4.code,NULL);

    //Concaténation de la falselist de la condition
    tmp = newLabel(&tds,nextquad);
    complete_list_quads($2.falselist, tmp);

    free_list_quad($2.falselist);
    free_list_quad($2.truelist);

    if(debug)
    {
      printf("statement -> IF confition tag bloc\n");
    }
  }

  | IF condition tag bloc ELSE tag_else bloc
  {
    //Concaténation de la truelist de la condition
    struct symbol* tmp = newLabel(&tds,$3);
    complete_list_quads($2.truelist, tmp);

    //Ajout d'un goto
    tmp = newLabel(&tds,nextquad);
    struct quads* newQuads = quadsGen("j", NULL, NULL, tmp);
    nextquad--;

    //Concaténation des blocs
    struct quads* codeTmp = quadsConcat($2.code,$4.code ,newQuads);

    //Concaténation de la falselist de la condition
    tmp = newLabel(&tds,$6);
    complete_list_quads($2.falselist, tmp);
    $$.code = quadsConcat(codeTmp,$7.code,NULL);

    free_list_quad($2.falselist);
    free_list_quad($2.truelist);

    if(debug)
    {
      printf("statement -> IF conditio tag bloc ELSE tag_else bloc\n");
    }
  }

  | FOR '(' attribution ';' tag condition ';' tag avancement_for tag {nextquad-=($10-$8);} ')' tag bloc
  {
    //Nouveau calcul du nextquad
    nextquad+=($10-$8);

    //Concaténation de la truelist de la condition
    struct symbol* tmp = newLabel(&tds,$13);
    complete_list_quads($6.truelist, tmp);
    struct quads* code_tmp = quadsConcat($3.code,$6.code,$14.code);

    //Ajout du goto begin
    tmp = newLabel(&tds,$5);
    struct quads* newQuads = quadsGen("j", NULL, NULL, tmp);
    code_tmp = quadsConcat(code_tmp,$9.code ,newQuads);

    //Concaténation de la falselist de la condition
    tmp = newLabel(&tds,nextquad);
    complete_list_quads($6.falselist, tmp);
    
    $$.code = code_tmp;

    free_list_quad($6.falselist);
    free_list_quad($6.truelist);

    if(debug)
    {
      printf("statement -> FOR ( attribution ; tag condition ; tag avancement_for ) tag bloc\n");
    }
  }
;

avancement_for:
  attribution
  {
    $$=$1;

    if(debug)
    {
      printf("avancement_for -> attribution\n");
    }
  }

  | expression
  {
    $$=$1;

    if(debug)
    {
      printf("avancement_for -> expression\n");
    }
  }
;


tag:
  {
    $$ = nextquad;

    if(debug)
    {
      printf("Tag\n");
    }
  }
;

tag_else:
  {
    nextquad++;
    $$ = nextquad;

    if(debug)
    {
      printf("Tag else\n");
    }
  }
;

code_line:
  attribution
  {
    $$=$1;

    if(debug)
    {
      printf("code_ligne -> attribution\n");
    }
  }

  | declaration
  {
    $$ = $1;

    if(debug)
    {
      printf("code_ligne -> declaration\n");
    }
  }

  | PRINTF '(' STRING ')'
  {
    struct symbol* tmp = newtemp(&tds);
    tmp->string = $3;
    tmp->type = STRING_TYPE;
    $$.code = quadsGen("printf",NULL,NULL,tmp);

    if(debug)
    {
      printf("code_ligne -> PRINTF '(' STRING ')'\n");
    }
  }

  | PRINTI '(' variable ')'
  {
    struct quads* newQuads = quadsGen("printi",NULL,NULL,$3.result);
    $$.code = quadsConcat($3.code,NULL,newQuads);

    if(debug)
    {
      printf("code_ligne -> PRINTI '(' variable ')'\n");
    }
  }

  | expression
  {
    $$=$1;

    if(debug)
    {
      printf("code_ligne -> expression\n");
    }
  }

  | RETURN expression
  {
    $$=$2;
    struct quads* newQuads = quadsGen("return",NULL,NULL,$2.result);
    $$.code = quadsConcat($2.code,newQuads,NULL);

    if(debug)
    {
      printf("code_ligne -> RETURN expression\n");
    }
  }
;

declaration:
  TYPE list_var
  {
    if($1 != $2.result->type)
    {
      printf("ERROR! Les variables declarées ne sont pas du bon type.\n");
      free_all();
      lex_free();
      exit(-1);
    }
    $$=$2;

    if(debug)
    {
      printf("declaration -> TYPE list_var\n");
    }
  }
;

list_var:
  var ',' list_var
  {
    if($1.result->type != $3.result->type)
    {
      printf("ERROR ! %s et %s n'ont pas le meme type\n",$1.result->name,$3.result->name);
      free_all();
      lex_free();
      exit(-1);
    }
    $$.code = quadsConcat($1.code,$3.code,NULL);

    if(debug)
    {
      printf("list_var -> var , list_var\n");
    }
  }

  | var
  {
    $$=$1;

    if(debug)
    {
      printf("list_var -> var\n");
    }
  }
;

var:
  variable_declaration
  {
    $$=$1;

    if(debug)
    {
      printf("var -> variable_declaration\n");
    }
  }

  | variable_declaration '=' expression
  {
    $$=$1;
    if($1.decal != NULL)
    {
      printf("ERROR ! %s est un tableau, impossible de mettre un int\n",$1.result->name);
      free_all();
      lex_free();
      exit(-1);
    }
    struct quads* newQuads = quadsGen("move",$3.result,NULL,$$.result);
    $$.code = quadsConcat($3.code,NULL,newQuads);

    if(debug)
    {
      printf("var -> variable_declaration = expression\n");
    }
  }

  | variable_declaration '=' array
  {
    $$ = $1;
    if($1.decal == NULL)
    {
      printf("ERROR ! Mise de tableau dans variable int\n");
      free_all();
      lex_free();
      exit(-1);
    }
    checkDims($1.result->size_dim,$3.list_dim->next);
    free_listDim($3.list_dim);
    $$.result->array_value = translateListToTab($3.list_number,$1.result->array_value);
    free_listNumber($3.list_number);

    if(debug)
    {
      printf("var -> variable_declaration = array\n");
    }
  }

  | IDENTIFIER '{' NUMBER ',' NUMBER '}' '=' array
  {
    struct symbol* tmp = lookup(tds,$1);

    if(tmp != NULL)
    {
      printf("ERROR ! Redéclaration de %s\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    checkDimsStencil($8.list_dim, $3, $5);
    free_listDim($8.list_dim);

    $$.result = add(&tds, $1, false);
    $$.result->type = STENCIL_TYPE;
    $$.result->value_tab_stenc = malloc(total_element($3,$5)*sizeof(int));

    $$.result->value_tab_stenc = translateListToTab($8.list_number,$$.result->value_tab_stenc); 
    $$.result->length_stenc = $8.list_number->size;
    free_listNumber($8.list_number);

    $$.result->is_array = true;
    $$.result->radius = $3;
    $$.result->nb_dim = $5;

    if(debug)
    {
      printf("var -> ID { NUMBER , NUMBER } = array\n");
    }
  }
;


variable:
  IDENTIFIER
  {
    struct symbol* tmp = lookup(tds,$1);

    if(tmp == NULL)
    {
      printf("ERROR : %s non déclaré\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    free($1);

    $$.result = tmp;
    $$.code = NULL;

    if(debug)
    {
      printf("variable -> ID\n");
    }
  }

  | index_attribution ']'
  {
    $$.result = newtemp(&tds);
    struct quads* newQuads = quadsGen("load_from_tab",$1.result,$1.decal,$$.result);
    $$.code = quadsConcat($1.code,NULL,newQuads);

    if(debug)
    {
      printf("variable -> index_attribution ]\n");
    }
  }
; 

variable_declaration:
  IDENTIFIER
  {
    struct symbol* tmp = lookup(tds,$1);

    if(tmp != NULL)
    {
      printf("ERROR! Redéclaration de %s\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    $$.result = add(&tds, $1, false);
    $$.result->type = INT_TYPE;
    $$.code = NULL;

    if(debug)
    {
      printf("variable_declaration -> ID\n");
    }
  }

  | index_declaration ']'
  {
    $1.result->length = $1.decal->value;
    $1.result->array_value = malloc($1.decal->value*sizeof(int));
    free($1.decal);
    $1.code = NULL;

    if(debug)
    {
      printf("variable_declaration -> index_declaration ]\n");
    }
  }
;

index_declaration:
  index_declaration DIM_SEPARATOR NUMBER
  {
    add_dim($1.result,$3);
    $$.nb_dim = $1.nb_dim+1;
    $$.result = $1.result;
    $$.decal->value = $1.decal->value*$3;
    $$.code = $1.code;


    if(debug)
    {
      printf("index_declaration -> index_declaration DIM_SEPARATOR NUMBER (%d)\n",$3);
    }
  }

  | IDENTIFIER '[' NUMBER
  {
    struct symbol* tmp = lookup(tds,$1);

    if(tmp != NULL)
    {
      printf("ERROR ! Redeclaration de %s\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    $$.result = add(&tds,$1,false);
    $$.result->is_array = true;
    add_dim($$.result,$3);
    $$.decal = (struct symbol*) malloc(sizeof(struct symbol));
    $$.decal->value = $3;
    $$.code = NULL;
    $$.nb_dim = 1;

    if(debug)
    {
      printf("index_declaration -> ID [ NUMBER (%d)\n",$3);
    }
  }
;

attribution:
  variable_attribution '=' expression
  {
    if($1.decal == NULL)
    {
      struct quads* newQuads = quadsGen("move",$3.result,NULL,$1.result);
      $$.code = quadsConcat($3.code,NULL,newQuads);
    }
    else
    {
      struct quads* newQuads = quadsGen("store_into_tab",$3.result,$1.decal,$1.result);
      $$.code = quadsConcat($1.code,$3.code,newQuads);
    }

    if(debug)
    {
      printf("attribution -> variable_attribution = expression\n");
    }
  }
;

variable_attribution:
  IDENTIFIER
  {
    struct symbol* tmp = lookup(tds,$1);

    if(tmp == NULL)
    {
      printf("ERROR : %s non déclaré\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    free($1);

    if(tmp->is_constant == true)
    {
      printf("Tentative de modification d'une constante\n");
      exit(-1);
    }

    $$.result = tmp;
    $$.code = NULL;

    if(debug)
    {
      printf("variable -> ID\n");
    }
  }

  | index_attribution ']'
  {
    $$ = $1;

    if(debug)
    {
      printf("variable -> index_attribution ]\n");
    }
  }
;

index_attribution:
  index_attribution DIM_SEPARATOR expression
  {
    $$.nb_dim = $1.nb_dim+1;
    struct symbol* symbol_size_dim = newtemp(&tds);
    symbol_size_dim->value = dim_size(tds,$1.result->name,$$.nb_dim);
    struct symbol* tmp1 = newtemp(&tds);
    struct symbol* tmp2 = newtemp(&tds);
    struct quads* quads1 = quadsGen("mul",$1.decal,symbol_size_dim,tmp1);
    struct quads* quads2 = quadsGen("addu",tmp1,$3.result,tmp2);
    $$.code = quadsConcat($1.code,$3.code,NULL);
    $$.code = quadsConcat($$.code,quads1,quads2);
    $$.result = $1.result;
    $$.decal = tmp2;

    if(debug)
    {
      printf("index_attribution -> index_attribution DIM_SEPARATOR expression\n");
    }
  }

  | IDENTIFIER '[' expression
  {
    $$.result = lookup(tds,$1);

    if($$.result == NULL)
    {
      printf("index: première utilisation de %s sans déclaration\n",$1);
      exit(-1);
    }

    free($1);

    if($$.result->is_constant == true)
    {
      printf("Tentative de modification de la constante %s\n",$1);
      exit(-1);
    }

    $$.decal = $3.result;
    $$.code = $3.code;
    $$.nb_dim = 1;

    if(debug)
    {
      printf("index_attribution -> ID [ expression\n");
    }

  }
;

array:
  '{' list_array '}'
  {
    $$ = $2;
    $$.list_dim = appendToListDim($2.list_dim,1);
    
    if(debug)
    {
      printf("array -> list_array\n");
    }
  }
;

list_array:
  array ',' list_array
  {
    checkDims($1.list_dim->next,$3.list_dim->next);

    $$.list_dim = $1.list_dim;
    $$.list_dim->size = $3.list_dim->size + 1;
    $$.list_number = concatListNumber($1.list_number,$3.list_number);

    if(debug)
    {
      printf("list_array -> array ',' list_array\n");
    }
  }

  | array
  {
    $$ = $1;

    if(debug)
    {
      printf("list_array -> array\n");
    }
  }

  | list_number
  {
    $$=$1;

    if(debug)
    {
      printf("list_array -> list_number\n");
    }
  }
;

list_number:
  NUMBER
  {
    struct listNumber* tmp = malloc(sizeof(struct listNumber));
    tmp->begin = NULL;
    $$.list_dim = appendToListDim(NULL,1);
    $$.list_number = addNumber(tmp,$1);
    $$.width = 1;

    if(debug)
    {
      printf("list_array -> NUMBER (%d)\n", $1);
    }

  }

  | list_number ',' NUMBER
  {
    $$.list_number = addNumber($1.list_number,$3);
    $$.list_dim = $1.list_dim;
    $$.list_dim->size = $1.list_dim->size + 1;

    if(debug)
    {
      printf("list_array -> NUMBER ',' list_array\n");
    }
 
  }
;

expression:
  expression '+' expression
  { 
    $$.result = newtemp(&tds);
    struct quads* newQuads = quadsGen("addu",$1.result,$3.result,$$.result);
    $$.code = quadsConcat($1.code,$3.code,newQuads);

    if(debug)
    {
      printf("expression -> expression + expression\n");
    }
  }

  | expression '-' expression
  { 
    $$.result = newtemp(&tds);
    struct quads* newQuads = quadsGen("subu",$1.result,$3.result,$$.result);
    $$.code = quadsConcat($1.code,$3.code,newQuads);

    if(debug)
    {
      printf("expression -> expression - expression\n");
    }
  }

  | expression '/' expression
  { 
    $$.result = newtemp(&tds);
    struct quads* newQuads = quadsGen("div",$1.result,$3.result,$$.result);
    $$.code = quadsConcat($1.code,$3.code,newQuads);

    if(debug)
    {
      printf("expression -> expression / expression\n");
    }
  }

  | expression '*' expression
  { 
    $$.result = newtemp(&tds);
    struct quads* newQuads = quadsGen("mul",$1.result,$3.result,$$.result);
    $$.code = quadsConcat($1.code,$3.code,newQuads);

    if(debug)
    {
      printf("expression -> expression * expression\n");
    }
  }

  | '(' expression ')'
  {
    $$=$2;

    if(debug)
    {
      printf("expression -> ( expression )\n");
    }

  }

  | '-' expression
  {
    $$.result = newtemp(&tds);
    struct symbol* arg1 = newtemp(&tds);
    arg1->value = 0;
    struct quads* newQuads= quadsGen("subu",arg1,$2.result,$$.result);
    $$.code = quadsConcat(NULL,$2.code,newQuads);

    if(debug)
    {
      printf("expression -> - expression\n");
    }

  }
  | INCR expression
  {
    $$.result = $2.result;
    struct symbol* arg = newtemp(&tds);
    arg->value = 1;
    struct quads* newQuads= quadsGen("addu",$2.result,arg,$2.result);
    $$.code = quadsConcat(NULL,$2.code,newQuads);

    if(debug)
    {
      printf("expression -> ++ expression\n");
    }
  }

  | DECR expression
  {
    $$.result = $2.result;
    struct symbol* arg = newtemp(&tds);
    arg->value = 1;
    struct quads* newQuads= quadsGen("subu",$2.result,arg,$2.result);
    $$.code = quadsConcat(NULL,$2.code,newQuads);

    if(debug)
    {
      printf("expression -> -- expression\n");
    }
  }

  | expression INCR
  {
    $$.result = $1.result;
    struct symbol* arg = newtemp(&tds);
    arg->value = 1;
    struct quads* newQuads= quadsGen("addu",$1.result,arg,$1.result);
    $$.code = quadsConcat(NULL,$1.code,newQuads);

    if(debug)
    {
      printf("expression -> expression ++\n");
    }
  }

  | expression DECR
  {
    $$.result = $1.result;
    struct symbol* arg = newtemp(&tds);
    arg->value = 1;
    struct quads* newQuads= quadsGen("subu",$1.result,arg,$1.result);
    $$.code = quadsConcat(NULL,$1.code,newQuads);

    if(debug)
    {
      printf("expression -> expression --\n");
    }

  }

  | variable
  {
    $$.result = $1.result;
    $$.code = $1.code;

    if(debug)
    {
      printf("expression -> variable\n");
    }
  }

  | NUMBER
  {
    $$.result = newtemp(&tds);
    $$.result->value = $1;
    $$.code = NULL;

    if(debug)
    {
      printf("expression -> NUMBER (%d)\n", $1);
    }
  }

  | IDENTIFIER '$' index_attribution ']'
  {
    struct symbol* stencil = lookup(tds,$1);
    if(stencil == NULL)
    {
      printf("ERROR ! %s non déclaré\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    free($1);

    if(stencil->type != STENCIL_TYPE)
    {
      printf("ERROR ! %s n'est pas un stencil\n",$1);
      free_all();
      lex_free();
      exit(-1);
    }

    int i;
    int nb_element = total_element(stencil->radius,stencil->nb_dim);
    struct symbol* tmp1 = newtemp(&tds);
    struct symbol* tmp2 = newtemp(&tds);
    struct symbol* tmp3 = newtemp(&tds);
    struct symbol* tmp4 = newtemp(&tds);
    struct symbol* tmp5 = newtemp(&tds);
    tmp5->value = 0;

    for(i=0;i<nb_element;i++)
    {
      struct symbol* shift = newtemp(&tds);
      shift->value = decalage($3.result->size_dim,stencil->radius,stencil->nb_dim,i);

      struct symbol* iterator = newtemp(&tds);
      iterator->value = i;

      struct quads* newQuads1 = quadsGen("addu",shift,$3.decal,tmp1);
      struct quads* newQuads2 = quadsGen("load_from_tab",$3.result,tmp1,tmp2);
      struct quads* newQuads3 = quadsGen("load_from_tab",stencil,iterator,tmp3);
      struct quads* newQuads4 = quadsGen("mul",tmp2,tmp3,tmp4);
      struct quads* newQuads5= quadsGen("addu",tmp4,tmp5,tmp5);

      $$.code = quadsConcat($3.code,newQuads1,newQuads2);
      $$.code = quadsConcat($$.code,newQuads3,newQuads4);
      $$.code = quadsConcat($$.code,newQuads5,NULL);
    }

    $$.result = tmp5;

    if(debug)
    {
      printf("expression -> ID $ index_attribution ]\n");
    }
  }

  | index_attribution ']' '$' IDENTIFIER
  {
    struct symbol* stencil = lookup(tds,$4);
    if(stencil == NULL)
    {
      printf("ERROR ! %s non déclaré\n",$4);
      free_all();
      lex_free();
      exit(-1);
    }

    free($4);

    if(stencil->type != STENCIL_TYPE)
    {
      printf("ERROR ! %s n'est pas un stencil\n",$4);
      free_all();
      lex_free();
      exit(-1);
    }

    int i;
    int nb_element = total_element(stencil->radius,stencil->nb_dim);
    struct symbol* tmp1 = newtemp(&tds);
    struct symbol* tmp2 = newtemp(&tds);
    struct symbol* tmp3 = newtemp(&tds);
    struct symbol* tmp4 = newtemp(&tds);
    struct symbol* tmp5 = newtemp(&tds);
    tmp5->value = 0;

    for(i=0;i<nb_element;i++)
    {
      struct symbol* shift = newtemp(&tds);
      shift->value = decalage($1.result->size_dim,stencil->radius,stencil->nb_dim,i);

      struct symbol* iterator = newtemp(&tds);
      iterator->value = i;

      struct quads* newQuads1 = quadsGen("addu",shift,$1.decal,tmp1);
      struct quads* newQuads2 = quadsGen("load_from_tab",$1.result,tmp1,tmp2);
      struct quads* newQuads3 = quadsGen("load_from_tab",stencil,iterator,tmp3);
      struct quads* newQuads4 = quadsGen("mul",tmp2,tmp3,tmp4);
      struct quads* newQuads5= quadsGen("addu",tmp4,tmp5,tmp5);

      $$.code = quadsConcat($1.code,newQuads1,newQuads2);
      $$.code = quadsConcat($$.code,newQuads3,newQuads4);
      $$.code = quadsConcat($$.code,newQuads5,NULL);
    }

    $$.result = tmp5;

    if(debug)
    {
      printf("expression -> index_attribution ] $ ID\n");
    }
  }
;

condition:  //condition booléenne
  expression EQUAL expression
  {
    struct quads* newQuads = quadsGen("beq",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression == expression\n");
    }
  }

  | expression NOTEQUAL expression
  {
    struct quads* newQuads = quadsGen("bne",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression != expression\n");
    }
  }

  | expression GREATEREQ expression
  {
    struct quads* newQuads = quadsGen("bge",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression >= expression\n");
    }
  }

  | expression '>' expression
  {
    struct quads* newQuads = quadsGen("bgt",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression > expression\n");
    }
  }

  | expression LOWEREQ expression
  {
    struct quads* newQuads = quadsGen("ble",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression <= expression\n");
    }
  }

  | expression '<' expression
  {
    struct quads* newQuads = quadsGen("blt",$1.result,$3.result,NULL);
    $$.truelist = new_list_quads(newQuads);
    struct quads* tmp = quadsConcat($1.code,$3.code,newQuads);

    newQuads = quadsGen("j",NULL,NULL,NULL);
    $$.falselist = new_list_quads(newQuads);
    $$.code = quadsConcat(tmp,NULL,newQuads);

    if(debug)
    {
      printf("condition -> expression < expression\n");
    }
  }

  | condition OR tag condition
  {
    struct symbol* tmp = newtemp(&tds);
    tmp->value = $3;
    complete_list_quads($1.falselist,tmp);
    $$.code = quadsConcat($1.code, $4.code, NULL);
    $$.truelist = concat_list_quads($1.truelist, $4.truelist);
    $$.falselist = $4.falselist;

    if(debug)
    {
      printf("condition -> condition || tag condition\n");
    }
  }

  | condition AND tag condition
  {
    struct symbol* tmp = newtemp(&tds);
    tmp->value = $3;
    complete_list_quads($1.truelist, tmp);
    $$.code = quadsConcat($1.code, $4.code, NULL);
    $$.falselist = concat_list_quads($1.falselist, $4.falselist);
    $$.truelist = $4.truelist;

    if(debug)
    {
      printf("condition -> condition && tag condition\n");
    }
  }

  | '!' condition
  {
    $$.code = $2.code;
    $$.falselist = $2.truelist;
    $$.truelist = $2.falselist;

    if(debug)
    {
      printf("condition -> ! condition\n");
    }
  }

  | '(' condition ')'
  {
    $$ = $2;

    if(debug)
    {
      printf("condition -> (condition)\n");
    }
  }
;


%%

void yyerror (char *s) {
    fprintf(stderr, "[Yacc] error: %s\n", s);
}

int main(int argc, char* argv[]) {
  if(argc >= 2)
  {
    if(strcmp(argv[1],"-d") == 0)
    {
      debug = 1;
    }
  }


  yyparse();
  if(debug)
  {
    printf("-----------------\nSymbol table:\n");
    print(tds);
    printf("-----------------\nQuad list:\n");
    quadsPrint(quadsFinal);
  }

  tradCodeFinal("out.s",quadsFinal,tds);

  //Free
  free_all();
  lex_free();

  return 0;
}
