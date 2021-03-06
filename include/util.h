#ifndef __UTIL_H__
#define __UTIL_H__

#include "tds.h"
#include "quads.h"
#include "list_quads.h"
#include "listNumber.h"
#include "enum.h"

void print_error(int, char*);
void free_tds(struct symbol*);
void free_code(struct quads*);
void free_list_quad(struct list_quads*);
void free_listNumber(struct listNumber*);
void free_listDim(struct dim*);
void free_all();

#endif