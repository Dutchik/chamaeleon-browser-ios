#include "chm_rules.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// ルールを2種に分けて索引化する:
//  (1) ドメイン型パターン（'.'を含み '/'':''*''?''#' 等を含まない）→ ハッシュ表。
//      評価時は URL の host からサフィックスを辿ってO(ラベル数)≒O(1)で判定
//      （host == pattern もしくは host が pattern のサブドメイン）。
//  (2) それ以外（"/ads/" 等のパス/部分一致）→ 小配列を strstr で線形走査。
//      通常この種は少数なので実効的に高速。
// これによりルール総数が増えても、ドメイン系はO(1)近似で判定できる。

#define NB 1024  // ハッシュバケット数（2の冪）

typedef struct dnode { char *dom; int action; struct dnode *next; } dnode;
static dnode *g_buckets[NB];
static int g_domain_count = 0;

typedef struct { char *pat; int action; } srule;
static srule *g_subs = NULL;
static int g_subn = 0, g_subcap = 0;

static char *dup_lower(const char *s) {
    size_t n = strlen(s);
    char *o = (char *)malloc(n + 1);
    if (!o) return NULL;
    for (size_t i = 0; i < n; i++) o[i] = (char)tolower((unsigned char)s[i]);
    o[n] = 0;
    return o;
}

static unsigned long fnv1a(const char *s) {
    unsigned long h = 1469598103934665603UL;
    while (*s) { h ^= (unsigned char)*s++; h *= 1099511628211UL; }
    return h;
}

static int is_domain_pattern(const char *p) {
    int hasdot = 0;
    for (const char *c = p; *c; c++) {
        char ch = *c;
        if (ch == '.') hasdot = 1;
        if (ch == '/' || ch == ':' || ch == '*' || ch == '?' || ch == '#' || ch == ' ') return 0;
    }
    return hasdot;
}

void chm_rules_clear(void) {
    for (int i = 0; i < NB; i++) {
        dnode *n = g_buckets[i];
        while (n) { dnode *nx = n->next; free(n->dom); free(n); n = nx; }
        g_buckets[i] = NULL;
    }
    g_domain_count = 0;
    for (int i = 0; i < g_subn; i++) free(g_subs[i].pat);
    free(g_subs); g_subs = NULL; g_subn = 0; g_subcap = 0;
}

static void domain_insert(char *dom_lower, int action) {
    unsigned long h = fnv1a(dom_lower) & (NB - 1);
    // 既存重複はスキップ（メモリ節約）
    for (dnode *n = g_buckets[h]; n; n = n->next) {
        if (strcmp(n->dom, dom_lower) == 0) { n->action = action; free(dom_lower); return; }
    }
    dnode *node = (dnode *)malloc(sizeof(dnode));
    if (!node) { free(dom_lower); return; }
    node->dom = dom_lower; node->action = action; node->next = g_buckets[h];
    g_buckets[h] = node;
    g_domain_count++;
}

void chm_rules_add(const char *pattern, int action) {
    if (!pattern || !*pattern) return;
    if (is_domain_pattern(pattern)) {
        char *d = dup_lower(pattern);
        if (d) domain_insert(d, action);
    } else {
        if (g_subn >= g_subcap) {
            int cap = g_subcap ? g_subcap * 2 : 16;
            srule *n = (srule *)realloc(g_subs, sizeof(srule) * cap);
            if (!n) return;
            g_subs = n; g_subcap = cap;
        }
        char *p = dup_lower(pattern);
        if (!p) return;
        g_subs[g_subn].pat = p; g_subs[g_subn].action = action; g_subn++;
    }
}

int chm_rules_count(void) { return g_domain_count + g_subn; }

// URL から host を取り出して小文字化（呼び出し側で free）
static char *host_of(const char *lower_url) {
    const char *p = strstr(lower_url, "://");
    p = p ? p + 3 : lower_url;
    const char *e = p;
    while (*e && *e != '/' && *e != '?' && *e != '#' && *e != ':') e++;
    size_t n = (size_t)(e - p);
    char *h = (char *)malloc(n + 1);
    if (!h) return NULL;
    memcpy(h, p, n); h[n] = 0;
    return h;
}

static int domain_lookup(const char *dom) {
    unsigned long h = fnv1a(dom) & (NB - 1);
    for (dnode *n = g_buckets[h]; n; n = n->next) {
        if (strcmp(n->dom, dom) == 0) return n->action;
    }
    return -1;
}

int chm_rules_eval(const char *url) {
    if (!url) return 0;
    char *lu = dup_lower(url);
    if (!lu) return 0;

    // (1) ドメイン系: host のサフィックスを順に照合（O(ラベル数)）
    if (g_domain_count > 0) {
        char *host = host_of(lu);
        if (host) {
            const char *cur = host;
            while (cur && *cur) {
                int a = domain_lookup(cur);
                if (a >= 0) { free(host); free(lu); return a; }
                const char *dot = strchr(cur, '.');
                cur = dot ? dot + 1 : NULL;   // 次の親ドメインへ
            }
            free(host);
        }
    }

    // (2) パス/部分一致系: 少数なので線形走査
    int act = 0;
    for (int i = 0; i < g_subn; i++) {
        if (strstr(lu, g_subs[i].pat)) { act = g_subs[i].action; break; }
    }
    free(lu);
    return act;
}
