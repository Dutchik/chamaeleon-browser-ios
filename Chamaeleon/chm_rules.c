#include "chm_rules.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct { char *pattern; int action; } chm_rule;

static chm_rule *g_rules = NULL;
static int g_count = 0;
static int g_cap = 0;

static char *dup_lower(const char *s) {
    size_t n = strlen(s);
    char *o = (char *)malloc(n + 1);
    if (!o) return NULL;
    for (size_t i = 0; i < n; i++) o[i] = (char)tolower((unsigned char)s[i]);
    o[n] = 0;
    return o;
}

void chm_rules_clear(void) {
    for (int i = 0; i < g_count; i++) free(g_rules[i].pattern);
    free(g_rules);
    g_rules = NULL; g_count = 0; g_cap = 0;
}

void chm_rules_add(const char *pattern, int action) {
    if (!pattern || !*pattern) return;
    if (g_count >= g_cap) {
        int cap = g_cap ? g_cap * 2 : 16;
        chm_rule *n = (chm_rule *)realloc(g_rules, sizeof(chm_rule) * cap);
        if (!n) return;
        g_rules = n; g_cap = cap;
    }
    char *p = dup_lower(pattern);
    if (!p) return;
    g_rules[g_count].pattern = p;
    g_rules[g_count].action = action;
    g_count++;
}

int chm_rules_count(void) { return g_count; }

int chm_rules_eval(const char *url) {
    if (!url) return 0;
    char *lu = dup_lower(url);
    if (!lu) return 0;
    int act = 0;
    for (int i = 0; i < g_count; i++) {
        if (strstr(lu, g_rules[i].pattern)) { act = g_rules[i].action; break; }
    }
    free(lu);
    return act;
}
