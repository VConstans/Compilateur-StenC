CC = gcc
LEX = lex
YACC = yacc -d #--report=all
CFLAGS = -O2 -Wall -Iinclude
LDFLAGS = -ly -lfl -Iinclude
EXEC = stenCil

stenCil: obj/quads.o obj/tds.o src/y.tab.c src/lex.yy.c
	$(CC) -g $^ -o stenCil  $(LDFLAGS)

src/y.tab.c: yacc/$(EXEC).y
	$(YACC) yacc/$(EXEC).y
	mv y.tab.c src/
	mv y.tab.h include/

src/lex.yy.c: lex/$(EXEC).l
	$(LEX) lex/$(EXEC).l
	mv lex.yy.c src/

obj/%.o: src/%.c
	$(CC) -g -o $@ -c $< $(CFLAGS)

clean:
	rm obj/*.o src/y.tab.c include/y.tab.h src/lex.yy.c stenCil
